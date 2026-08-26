#!/usr/bin/env bash
#
# whatsapp.sh - gerencia a conexao do WhatsApp.
#
#   ./whatsapp.sh connect              conecta lendo o QR code no terminal
#   ./whatsapp.sh connect 5511999999999   conecta por codigo de 8 digitos
#   ./whatsapp.sh status               mostra se esta conectado
#   ./whatsapp.sh list                 lista todas as instancias
#   ./whatsapp.sh restart              reinicia a conexao
#   ./whatsapp.sh logout               desconecta o celular (mantem a config)
#   ./whatsapp.sh delete               apaga a instancia por completo
#
# Variaveis: INSTANCE (padrao meu-whatsapp), API_URL, API_KEY.

set -euo pipefail

API_URL="${API_URL:-http://localhost:8080}"
INSTANCE="${INSTANCE:-meu-whatsapp}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.local.yaml}"

if [[ -f .env ]]; then
  API_KEY="${API_KEY:-$(grep -E '^AUTHENTICATION_API_KEY=' .env | head -1 | cut -d= -f2-)}"
fi
API_KEY="${API_KEY:-}"

if [[ -z "$API_KEY" || "$API_KEY" == troque-esta-chave* ]]; then
  echo "ERRO: AUTHENTICATION_API_KEY nao configurada no .env" >&2
  exit 1
fi

api() {
  local method=$1 path=$2
  curl -sS -X "$method" "$API_URL$path" -H "apikey: $API_KEY" -H 'Content-Type: application/json'
}

pyget() { python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for k in '$1'.split('.'):
    d = d.get(k) if isinstance(d, dict) else None
    if d is None: break
print(d if d is not None else '')
"; }

# Desenha o QR code no terminal. Usa o qrcode-terminal, que ja e dependencia do
# projeto - localmente se houver node_modules, senao dentro do container.
render_qr() {
  local code=$1
  local snippet="require('qrcode-terminal').generate(process.argv[1],{small:true})"

  if [[ -d node_modules/qrcode-terminal ]]; then
    node -e "$snippet" "$code" && return 0
  fi

  if command -v docker >/dev/null 2>&1 && [[ -f "$COMPOSE_FILE" ]]; then
    if docker compose -f "$COMPOSE_FILE" exec -T api node -e "$snippet" "$code" 2>/dev/null; then
      return 0
    fi
  fi

  return 1
}

cmd_status() {
  local state
  state=$(api GET "/instance/connectionState/$INSTANCE" | pyget "instance.state")
  case "$state" in
    open)       echo "CONECTADO - a instancia '$INSTANCE' esta ativa." ;;
    connecting) echo "CONECTANDO - aguardando leitura do QR code." ;;
    close|"")   echo "DESCONECTADO - rode: ./whatsapp.sh connect" ;;
    *)          echo "Estado: $state" ;;
  esac
}

cmd_list() {
  api GET "/instance/fetchInstances" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if not d:
    print('Nenhuma instancia criada ainda.'); raise SystemExit
print(f\"{'INSTANCIA':<24} {'ESTADO':<14} NUMERO\")
for i in d:
    inst = i.get('instance', i)
    print(f\"{str(inst.get('instanceName') or inst.get('name','?')):<24} \"
          f\"{str(inst.get('connectionStatus') or inst.get('status','?')):<14} \"
          f\"{inst.get('ownerJid') or inst.get('number') or '-'}\")
"
}

cmd_connect() {
  local number="${1:-}"

  # Cria a instancia se ainda nao existir.
  if ! api GET "/instance/connectionState/$INSTANCE" | grep -q '"state"'; then
    echo "Criando a instancia '$INSTANCE'..."
    curl -sS -X POST "$API_URL/instance/create" -H "apikey: $API_KEY" -H 'Content-Type: application/json' \
      -d "{\"instanceName\":\"$INSTANCE\",\"qrcode\":false,\"integration\":\"WHATSAPP-BAILEYS\"}" >/dev/null
    sleep 2
  fi

  local state
  state=$(api GET "/instance/connectionState/$INSTANCE" | pyget "instance.state")
  if [[ "$state" == "open" ]]; then
    echo "Este WhatsApp ja esta conectado. Para trocar de numero: ./whatsapp.sh logout"
    return 0
  fi

  local path="/instance/connect/$INSTANCE"
  [[ -n "$number" ]] && path="$path?number=$number"

  # A API espera apenas 2s pelo QR e pode devolver vazio ({"count":0}) enquanto
  # o socket ainda esta subindo. Insiste ate o codigo aparecer.
  local resp pairing code
  for _ in $(seq 1 10); do
    resp=$(api GET "$path")
    pairing=$(echo "$resp" | pyget "pairingCode")
    code=$(echo "$resp" | pyget "code")
    [[ -n "$pairing" || -n "$code" ]] && break
    sleep 2
  done

  echo ""
  if [[ -n "$number" && -n "$pairing" ]]; then
    echo "  Codigo de pareamento: ${pairing}"
    echo ""
    echo "  No celular: WhatsApp > Aparelhos conectados > Conectar aparelho"
    echo "              > Conectar com numero de telefone > digite o codigo acima"
  elif [[ -n "$code" ]]; then
    if render_qr "$code"; then
      echo "  Escaneie o QR code acima com o WhatsApp do celular:"
    else
      # Sem como desenhar: grava o PNG que a API devolve.
      echo "$resp" | python3 -c "
import sys, json, base64
b64 = (json.load(sys.stdin).get('base64') or '').split(',')[-1]
if b64:
    open('qrcode.png','wb').write(base64.b64decode(b64))
    print('  QR code salvo em qrcode.png - abra o arquivo e escaneie.')
else:
    print('  Nao foi possivel obter o QR code.')
"
      echo "  Depois:"
    fi
    echo "  WhatsApp > Aparelhos conectados > Conectar aparelho"
    echo ""
    echo "  Dica: sem interface grafica? Use o codigo numerico:"
    echo "        ./whatsapp.sh connect SEUNUMEROCOMDDD"
  else
    echo "Nao consegui obter o QR code." >&2
    echo "" >&2
    echo "Quase sempre isso significa que o servidor nao alcanca o WhatsApp." >&2
    echo "Teste a saida de rede com:" >&2
    echo "    curl -I https://web.whatsapp.com" >&2
    echo "" >&2
    echo "Se estiver bloqueado, libere o acesso a web.whatsapp.com (443) ou" >&2
    echo "configure PROXY_HOST/PROXY_PORT no .env." >&2
    echo "" >&2
    echo "Logs do servidor:  docker compose -f $COMPOSE_FILE logs -n 50 api" >&2
    echo "Resposta recebida: $(echo "$resp" | head -c 200)" >&2
    return 1
  fi

  echo ""
  echo "Aguardando a conexao (Ctrl+C para sair)..."
  for i in $(seq 1 60); do
    state=$(api GET "/instance/connectionState/$INSTANCE" | pyget "instance.state")
    if [[ "$state" == "open" ]]; then
      echo ""
      echo "WhatsApp conectado com sucesso."
      return 0
    fi
    printf "\r  %ss" $((i * 3))
    sleep 3
  done

  echo ""
  echo "Ainda nao conectou. O QR expira rapido - rode o comando de novo." >&2
  return 1
}

cmd_restart() { api POST "/instance/restart/$INSTANCE" >/dev/null && echo "Instancia reiniciada."; }

cmd_logout() {
  api DELETE "/instance/logout/$INSTANCE" >/dev/null
  echo "Celular desconectado. A configuracao do filtro foi mantida."
  echo "Para conectar outro numero: ./whatsapp.sh connect"
}

cmd_delete() {
  read -r -p "Apagar a instancia '$INSTANCE' e toda a configuracao? [s/N] " ok
  [[ "$ok" == "s" || "$ok" == "S" ]] || { echo "Cancelado."; return 0; }
  api DELETE "/instance/delete/$INSTANCE" >/dev/null && echo "Instancia apagada."
}

case "${1:-help}" in
  connect) cmd_connect "${2:-}" ;;
  status)  cmd_status ;;
  list)    cmd_list ;;
  restart) cmd_restart ;;
  logout)  cmd_logout ;;
  delete)  cmd_delete ;;
  *)
    sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
