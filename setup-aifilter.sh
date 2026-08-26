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

# Le as chaves do .env
if [[ -f .env ]]; then
  API_KEY="${API_KEY:-$(grep -E '^AUTHENTICATION_API_KEY=' .env | head -1 | cut -d= -f2-)}"
  OPENAI_KEY="${OPENAI_KEY:-$(grep -E '^OPENAI_API_KEY_GLOBAL=' .env | head -1 | cut -d= -f2-)}"
  AI_PROVIDER="${AI_PROVIDER:-$(grep -E '^AI_PROVIDER=' .env | head -1 | cut -d= -f2-)}"
  AI_MODEL="${AI_MODEL:-$(grep -E '^AI_MODEL=' .env | head -1 | cut -d= -f2-)}"
fi

API_KEY="${API_KEY:-}"
OPENAI_KEY="${OPENAI_KEY:-}"
AI_PROVIDER="${AI_PROVIDER:-groq}"
AI_MODEL="${AI_MODEL:-}"

# Provedores compativeis com a API da OpenAI. Os quatro primeiros tem plano gratuito.
case "$AI_PROVIDER" in
  groq)
    AI_BASE_URL="https://api.groq.com/openai/v1"
    AI_MODEL="${AI_MODEL:-llama-3.3-70b-versatile}"
    KEY_HELP="https://console.groq.com/keys (gratuito)" ;;
  gemini)
    AI_BASE_URL="https://generativelanguage.googleapis.com/v1beta/openai"
    AI_MODEL="${AI_MODEL:-gemini-2.0-flash}"
    KEY_HELP="https://aistudio.google.com/apikey (gratuito)" ;;
  openrouter)
    AI_BASE_URL="https://openrouter.ai/api/v1"
    AI_MODEL="${AI_MODEL:-meta-llama/llama-3.3-70b-instruct:free}"
    KEY_HELP="https://openrouter.ai/keys (tem modelos :free)" ;;
  ollama)
    AI_BASE_URL="${OLLAMA_URL:-http://localhost:11434/v1}"
    AI_MODEL="${AI_MODEL:-llama3.1}"
    OPENAI_KEY="${OPENAI_KEY:-ollama}"
    KEY_HELP="nao precisa de chave (roda na sua maquina)" ;;
  openai)
    AI_BASE_URL=""
    AI_MODEL="${AI_MODEL:-gpt-4o-mini}"
    KEY_HELP="https://platform.openai.com/api-keys (PAGO)" ;;
  *)
    echo "ERRO: AI_PROVIDER invalido: '$AI_PROVIDER'" >&2
    echo "      Use: groq | gemini | openrouter | ollama | openai" >&2
    exit 1 ;;
esac

if [[ -z "$API_KEY" || "$API_KEY" == troque-esta-chave* ]]; then
  echo "ERRO: AUTHENTICATION_API_KEY nao configurada no .env" >&2
  echo "      Gere uma com: openssl rand -hex 32" >&2
  exit 1
fi

if [[ -z "$OPENAI_KEY" || "$OPENAI_KEY" == cole-sua-chave* || "$OPENAI_KEY" == sk-cole-sua-chave* ]]; then
  echo "ERRO: OPENAI_API_KEY_GLOBAL nao configurada no .env" >&2
  echo "      Provedor atual: $AI_PROVIDER - pegue a chave em $KEY_HELP" >&2
  exit 1
fi

echo "Provedor de IA: $AI_PROVIDER   modelo: $AI_MODEL"
[[ -n "$AI_BASE_URL" ]] && echo "Endpoint .....: $AI_BASE_URL"
echo ""

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

echo "==> 2/5 e 3/5 Conectando o WhatsApp"
# A conexao fica a cargo do whatsapp.sh, que desenha o QR no proprio terminal
# e ainda aceita conectar por codigo de 8 digitos (util em servidor sem tela).
if [[ -x ./whatsapp.sh ]]; then
  if INSTANCE="$INSTANCE" API_URL="$API_URL" API_KEY="$API_KEY" ./whatsapp.sh connect "${PHONE_NUMBER:-}"; then
    echo ""
  else
    echo ""
    echo "AVISO: o WhatsApp ainda nao conectou." >&2
    echo "       O filtro sera configurado assim mesmo; depois rode: ./whatsapp.sh connect" >&2
    echo ""
  fi
else
  echo "AVISO: whatsapp.sh nao encontrado - pulando a conexao." >&2
  echo "       Conecte depois com: ./whatsapp.sh connect" >&2
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
  \"model\": \"$AI_MODEL\",
  \"apiBaseUrl\": \"$AI_BASE_URL\",
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
  # Rodar o script de novo e' comum; nesse caso o filtro ja existe.
  BOT_ID=$(api GET "/aiFilter/find/$INSTANCE" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d[0]['id'] if isinstance(d,list) and d else '')
except Exception: print('')
")
  if [[ -n "$BOT_ID" ]]; then
    echo "    Filtro ja existia, reaproveitando. botId: $BOT_ID"
  else
    echo "    ERRO: nao consegui criar nem localizar o filtro." >&2
    echo "    Resposta do servidor: $BOT" >&2
    exit 1
  fi
fi

echo ""
echo "================================================================"
echo " Pronto."
echo ""
echo " Instancia .......: $INSTANCE"
echo " Provedor de IA ..: $AI_PROVIDER ($AI_MODEL)"
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
echo " Gerenciar a conexao do WhatsApp:"
echo "   ./whatsapp.sh status     ver se esta conectado"
echo "   ./whatsapp.sh connect    conectar (QR no terminal)"
echo "   ./whatsapp.sh connect 5511999999999   conectar por codigo, sem QR"
echo "   ./whatsapp.sh logout     trocar de numero"
echo ""
echo " Ver conversas paradas para atendimento humano:"
echo "   curl -H 'apikey: \$API_KEY' $API_URL/aiFilter/fetchSessions/$BOT_ID/$INSTANCE"
echo ""
echo " Responder manualmente:"
echo "   curl -X POST $API_URL/message/sendText/$INSTANCE \\"
echo "     -H 'apikey: \$API_KEY' -H 'Content-Type: application/json' \\"
echo "     -d '{\"number\":\"5511999999999\",\"text\":\"Ola!\"}'"
echo "================================================================"
