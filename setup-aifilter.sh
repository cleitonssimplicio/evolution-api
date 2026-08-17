#!/usr/bin/env bash
#
# setup-aifilter.sh - conecta um WhatsApp e configura o filtro de IA.
#
#   ./setup-aifilter.sh
#
# Requisitos: curl e python3 (ambos ja vem instalados no Linux e no macOS).
# O servidor precisa estar rodando (docker compose -f docker-compose.local.yaml up -d).

set -euo pipefail

API_URL="${API_URL:-http://localhost:8080}"
INSTANCE="${INSTANCE:-meu-whatsapp}"
QR_FILE="${QR_FILE:-qrcode.png}"

# Le a chave da API e a chave da OpenAI do .env
if [[ -f .env ]]; then
  API_KEY="${API_KEY:-$(grep -E '^AUTHENTICATION_API_KEY=' .env | head -1 | cut -d= -f2-)}"
  OPENAI_KEY="${OPENAI_KEY:-$(grep -E '^OPENAI_API_KEY_GLOBAL=' .env | head -1 | cut -d= -f2-)}"
fi

API_KEY="${API_KEY:-}"
OPENAI_KEY="${OPENAI_KEY:-}"

if [[ -z "$API_KEY" || "$API_KEY" == troque-esta-chave* ]]; then
  echo "ERRO: AUTHENTICATION_API_KEY nao configurada no .env" >&2
  echo "      Gere uma com: openssl rand -hex 32" >&2
  exit 1
fi

if [[ -z "$OPENAI_KEY" || "$OPENAI_KEY" == sk-cole-sua-chave* ]]; then
  echo "ERRO: OPENAI_API_KEY_GLOBAL nao configurada no .env" >&2
  echo "      Pegue a sua em https://platform.openai.com/api-keys" >&2
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

echo "==> 1/5 Aguardando a API subir em $API_URL"
for i in $(seq 1 60); do
  if curl -sSf "$API_URL" >/dev/null 2>&1; then echo "    API no ar."; break; fi
  [[ $i -eq 60 ]] && { echo "ERRO: API nao respondeu. Veja: docker compose -f docker-compose.local.yaml logs api" >&2; exit 1; }
  sleep 2
done

echo "==> 2/5 Criando a instancia '$INSTANCE'"
CREATE=$(api POST /instance/create "{\"instanceName\":\"$INSTANCE\",\"qrcode\":true,\"integration\":\"WHATSAPP-BAILEYS\"}" || true)

if echo "$CREATE" | grep -q 'already in use'; then
  echo "    Instancia ja existe, reaproveitando."
  CREATE=$(api GET "/instance/connect/$INSTANCE")
fi

echo "$CREATE" | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)
qr = d.get('qrcode') or d
b64 = (qr.get('base64') or '').split(',')[-1]
if not b64:
    print('SEM_QR')
    sys.exit(0)
open('$QR_FILE','wb').write(base64.b64decode(b64))
print('QR_OK')
" > /tmp/.aifilter_qr_status

if grep -q QR_OK /tmp/.aifilter_qr_status; then
  echo ""
  echo "    QR code salvo em: $QR_FILE"
  echo "    Abra o arquivo e escaneie com o WhatsApp do celular:"
  echo "      WhatsApp > Configuracoes > Aparelhos conectados > Conectar aparelho"
  echo ""
  echo "    (ou use a interface web em http://localhost:3000)"
  # Tenta abrir a imagem automaticamente
  (command -v xdg-open >/dev/null && xdg-open "$QR_FILE" >/dev/null 2>&1) || \
  (command -v open >/dev/null && open "$QR_FILE" >/dev/null 2>&1) || true
else
  echo "    Instancia ja conectada ou sem QR pendente."
fi

echo ""
echo "==> 3/5 Aguardando voce escanear o QR code (ate 3 minutos)"
CONNECTED=false
for i in $(seq 1 90); do
  STATE=$(api GET "/instance/connectionState/$INSTANCE" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print((d.get('instance') or {}).get('state') or '')
except Exception:
    print('')
" || echo "")
  if [[ "$STATE" == "open" ]]; then CONNECTED=true; echo "    WhatsApp conectado!"; break; fi
  printf "\r    aguardando... (%ss)" $((i*2))
  sleep 2
done
echo ""

if [[ "$CONNECTED" != true ]]; then
  echo "AVISO: ainda nao conectou. O QR expira em ~40s - rode o script de novo para gerar outro." >&2
  echo "       Voce ainda pode configurar o filtro depois de conectar." >&2
fi

echo "==> 4/5 Cadastrando as credenciais da OpenAI"
CREDS=$(api POST "/openai/creds/$INSTANCE" "{\"name\":\"aifilter-key\",\"apiKey\":\"$OPENAI_KEY\"}" || true)
CREDS_ID=$(echo "$CREDS" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin); print(d.get('id') or '')
except Exception: print('')
")

if [[ -z "$CREDS_ID" ]]; then
  CREDS_ID=$(api GET "/openai/creds/$INSTANCE" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d[0]['id'] if isinstance(d,list) and d else '')
except Exception: print('')
")
fi

[[ -z "$CREDS_ID" ]] && { echo "ERRO: nao consegui cadastrar as credenciais da OpenAI." >&2; echo "$CREDS" >&2; exit 1; }
echo "    credsId: $CREDS_ID"

echo "==> 5/5 Criando o filtro de IA"
BOT=$(api POST "/aiFilter/create/$INSTANCE" "{
  \"enabled\": true,
  \"description\": \"Filtro de IA principal\",
  \"openaiCredsId\": \"$CREDS_ID\",
  \"model\": \"gpt-4o-mini\",
  \"triggerType\": \"all\",
  \"systemPrompt\": \"Voce classifica mensagens recebidas no WhatsApp de um negocio. Seja preciso e responda sempre em portugues do Brasil.\",
  \"autoRespondPrompt\": \"Voce e um atendente virtual educado e objetivo. Responda em portugues do Brasil, em no maximo 3 frases.\",
  \"filterCategories\": [
    {\"name\": \"duvida\", \"description\": \"Perguntas sobre produtos, precos, horarios ou funcionamento\", \"action\": \"auto_respond\"},
    {\"name\": \"saudacao\", \"description\": \"Cumprimentos e mensagens sociais simples\", \"action\": \"auto_respond\", \"responseTemplate\": \"Cumprimente de volta e pergunte como pode ajudar.\"},
    {\"name\": \"negociacao\", \"description\": \"Pedidos de desconto, fechamento de venda, reclamacoes ou assuntos sensiveis\", \"action\": \"flag_human\"},
    {\"name\": \"spam\", \"description\": \"Propaganda, corrente, golpe ou mensagem irrelevante\", \"action\": \"ignore\"}
  ],
  \"expire\": 0,
  \"keywordFinish\": \"#sair\",
  \"delayMessage\": 1000,
  \"unknownMessage\": \"Um atendente vai te responder em instantes.\",
  \"listeningFromMe\": false,
  \"stopBotFromMe\": true,
  \"keepOpen\": true,
  \"debounceTime\": 3,
  \"ignoreJids\": [\"@g.us\"],
  \"splitMessages\": false,
  \"timePerChar\": 0
}" || true)

BOT_ID=$(echo "$BOT" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin); print(d.get('id') or '')
except Exception: print('')
")

if [[ -n "$BOT_ID" ]]; then
  echo "    Filtro criado. botId: $BOT_ID"
else
  echo "    Resposta do servidor:"
  echo "$BOT"
fi

echo ""
echo "================================================================"
echo " Pronto."
echo ""
echo " Instancia .......: $INSTANCE"
echo " Painel web ......: http://localhost:3000"
echo " API .............: $API_URL"
echo ""
echo " Categorias configuradas:"
echo "   duvida     -> a IA responde sozinha"
echo "   saudacao   -> a IA responde sozinha"
echo "   negociacao -> pausa e chama voce (status 'paused')"
echo "   spam       -> ignora"
echo ""
echo " Grupos estao sendo ignorados (ignoreJids: @g.us)."
echo " Mande uma mensagem de outro celular para testar."
echo ""
echo " Ver conversas paradas para atendimento humano:"
echo "   curl -H 'apikey: \$API_KEY' $API_URL/aiFilter/fetchSessions/$BOT_ID/$INSTANCE"
echo ""
echo " Responder manualmente:"
echo "   curl -X POST $API_URL/message/sendText/$INSTANCE \\"
echo "     -H 'apikey: \$API_KEY' -H 'Content-Type: application/json' \\"
echo "     -d '{\"number\":\"5511999999999\",\"text\":\"Ola!\"}'"
echo "================================================================"
