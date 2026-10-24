#!/usr/bin/env bash
#
# monitor.sh - acompanha o que o filtro de IA esta decidindo e responde
#              as conversas que ele passou para atendimento humano.
#
#   ./monitor.sh                          painel ao vivo (atualiza sozinho)
#   ./monitor.sh sessoes                  lista as conversas uma vez
#   ./monitor.sh pausadas                 so as que esperam voce responder
#   ./monitor.sh decisoes                 o que a IA classificou (logs ao vivo)
#   ./monitor.sh responder 5511999999999 "Ola, tudo bem?"
#   ./monitor.sh reabrir 5511999999999    devolve a conversa para a IA
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
  local method=$1 path=$2 body=${3:-}
  if [[ -n "$body" ]]; then
    curl -sS -X "$method" "$API_URL$path" \
      -H "apikey: $API_KEY" -H 'Content-Type: application/json' -d "$body"
  else
    curl -sS -X "$method" "$API_URL$path" -H "apikey: $API_KEY"
  fi
}

bot_id() {
  api GET "/aiFilter/find/$INSTANCE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d[0]['id'] if isinstance(d, list) and d else '')
except Exception:
    print('')
"
}

# Converte um numero digitado pelo usuario no remoteJid do WhatsApp.
to_jid() {
  local n=${1//[^0-9]/}
  [[ "$n" == *"@"* ]] && { echo "$1"; return; }
  echo "${n}@s.whatsapp.net"
}

fetch_sessions() {
  local id
  id=$(bot_id)
  if [[ -z "$id" ]]; then
    echo "ERRO: nenhum filtro de IA encontrado na instancia '$INSTANCE'." >&2
    echo "      Rode primeiro: ./setup-aifilter.sh" >&2
    return 1
  fi
  api GET "/aiFilter/fetchSessions/$id/$INSTANCE"
}

print_sessions() {
  local filtro=${1:-todas}
  local dados
  dados=$(fetch_sessions) || return 1
  printf '%s' "$dados" | python3 -c "
import sys, json
from datetime import datetime

filtro = '$filtro'
try:
    d = json.load(sys.stdin)
except Exception:
    print('Nao consegui ler as sessoes.'); raise SystemExit(1)

if not isinstance(d, list):
    print('Resposta inesperada:', str(d)[:200]); raise SystemExit(1)

if filtro == 'pausadas':
    d = [s for s in d if s.get('status') == 'paused']

if not d:
    print('  (nenhuma conversa' + (' aguardando atendimento' if filtro == 'pausadas' else '') + ')')
    raise SystemExit

rotulo = {
    'paused': 'ESPERANDO VOCE',
    'opened': 'IA respondendo',
    'closed': 'encerrada',
}

d.sort(key=lambda s: (s.get('status') != 'paused', s.get('updatedAt') or ''), reverse=False)

print(f\"  {'NUMERO':<20} {'SITUACAO':<16} {'NOME':<20} ATUALIZADA\")
for s in d:
    jid = (s.get('remoteJid') or '')
    numero = jid.split('@')[0]
    st = s.get('status') or '?'
    quando = (s.get('updatedAt') or '')[:19].replace('T', ' ')
    nome = (s.get('pushName') or '-')[:19]
    print(f'  {numero:<20} {rotulo.get(st, st):<16} {nome:<20} {quando}')

pausadas = [s for s in d if s.get('status') == 'paused']
if pausadas and filtro != 'pausadas':
    print()
    print(f'  {len(pausadas)} conversa(s) esperando voce responder.')
"
}

cmd_painel() {
  local id
  id=$(bot_id) || true
  while true; do
    clear
    echo "=============================================================="
    echo " Filtro de IA - instancia '$INSTANCE'"
    echo " $(date '+%d/%m/%Y %H:%M:%S')   (Ctrl+C para sair)"
    echo "=============================================================="
    echo ""

    local estado
    estado=$(api GET "/instance/connectionState/$INSTANCE" | python3 -c "
import sys, json
try:
    print((json.load(sys.stdin).get('instance') or {}).get('state') or '?')
except Exception:
    print('?')
")
    case "$estado" in
      open) echo " WhatsApp: CONECTADO" ;;
      *)    echo " WhatsApp: $estado  (rode ./whatsapp.sh connect)" ;;
    esac
    echo ""
    echo " CONVERSAS"
    print_sessions todas || true
    echo ""
    echo " Para responder alguem que esta esperando:"
    echo "   ./monitor.sh responder NUMERO \"sua mensagem\""
    sleep 5
  done
}

cmd_decisoes() {
  echo "Mostrando o que a IA esta classificando. Ctrl+C para sair."
  echo "(mande uma mensagem de outro celular para ver aparecer aqui)"
  echo ""
  if docker compose -f "$COMPOSE_FILE" ps --status running 2>/dev/null | grep -q evolution_api; then
    docker compose -f "$COMPOSE_FILE" logs -f --tail 30 api 2>&1 \
      | grep --line-buffered -iE "AiFilter|Classified as" \
      | sed -u -E 's/.*Classified as: /  classificou -> /; s/.*\[AiFilterService\][^ ]* //'
  else
    echo "Container nao esta rodando. Se voce subiu com 'npm start', use:" >&2
    echo "  tail -f <seu-log> | grep AiFilter" >&2
    return 1
  fi
}

cmd_responder() {
  local numero=${1:-} texto=${2:-}
  if [[ -z "$numero" || -z "$texto" ]]; then
    echo "Uso: ./monitor.sh responder 5511999999999 \"sua mensagem\"" >&2
    return 1
  fi

  local resp
  resp=$(api POST "/message/sendText/$INSTANCE" \
    "$(python3 -c "
import json, sys
print(json.dumps({'number': sys.argv[1], 'text': sys.argv[2]}))
" "${numero//[^0-9]/}" "$texto")")

  if echo "$resp" | grep -q '"key"'; then
    echo "Mensagem enviada para $numero."
    echo ""
    echo "A conversa continua pausada (a IA nao vai interferir)."
    echo "Quando terminar o atendimento, devolva para a IA com:"
    echo "  ./monitor.sh reabrir $numero"
  elif echo "$resp" | grep -qi "Connection Closed\|connectionState"; then
    echo "Nao consegui enviar: o WhatsApp nao esta conectado." >&2
    echo "Conecte primeiro com: ./whatsapp.sh connect" >&2
    return 1
  else
    echo "Nao consegui enviar." >&2
    echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    m = d.get('response', {}).get('message') or d.get('message') or d
    print('  ' + (m if isinstance(m, str) else json.dumps(m)[:200]))
except Exception:
    print('  ' + sys.stdin.read()[:200])
" >&2
    return 1
  fi
}

cmd_reabrir() {
  local numero=${1:-}
  [[ -z "$numero" ]] && { echo "Uso: ./monitor.sh reabrir 5511999999999" >&2; return 1; }

  local jid
  jid=$(to_jid "$numero")
  api POST "/aiFilter/changeStatus/$INSTANCE" \
    "{\"remoteJid\":\"$jid\",\"status\":\"opened\"}" >/dev/null
  echo "Conversa com $numero devolvida para a IA."
}

case "${1:-painel}" in
  painel)    cmd_painel ;;
  sessoes)   echo " CONVERSAS"; print_sessions todas ;;
  pausadas)  echo " AGUARDANDO ATENDIMENTO HUMANO"; print_sessions pausadas ;;
  decisoes)  cmd_decisoes ;;
  responder) cmd_responder "${2:-}" "${3:-}" ;;
  reabrir)   cmd_reabrir "${2:-}" ;;
  *)         sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
