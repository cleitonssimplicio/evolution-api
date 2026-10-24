#!/usr/bin/env bash
#
# instalar.sh - instalacao guiada, do zero ate o WhatsApp conectado.
#
#   ./instalar.sh
#
# Faz tudo: confere os requisitos, pergunta a chave da IA, gera o .env,
# sobe os containers e conecta o seu WhatsApp.

set -euo pipefail

COMPOSE_FILE="docker-compose.local.yaml"
ENV_FILE=".env"

titulo() {
  echo ""
  echo "=============================================================="
  echo " $1"
  echo "=============================================================="
  echo ""
}

# ---------------------------------------------------------------- requisitos
titulo "Passo 1 de 5 - Conferindo o que voce precisa ter instalado"

faltou=0

if command -v docker >/dev/null 2>&1; then
  echo "  [ok] Docker instalado"
else
  echo "  [!!] Docker NAO encontrado"
  echo "       Instale em: https://docs.docker.com/get-docker/"
  faltou=1
fi

if docker compose version >/dev/null 2>&1; then
  echo "  [ok] Docker Compose instalado"
elif [[ $faltou -eq 0 ]]; then
  echo "  [!!] Docker Compose NAO encontrado"
  echo "       Atualize o Docker Desktop, ou instale o plugin docker-compose."
  faltou=1
fi

if [[ $faltou -eq 0 ]] && ! docker info >/dev/null 2>&1; then
  echo "  [!!] O Docker esta instalado mas NAO esta rodando."
  echo "       Abra o Docker Desktop e espere ele iniciar."
  faltou=1
fi

if command -v curl >/dev/null 2>&1; then echo "  [ok] curl"; else echo "  [!!] curl nao encontrado"; faltou=1; fi
if command -v python3 >/dev/null 2>&1; then echo "  [ok] python3"; else echo "  [!!] python3 nao encontrado"; faltou=1; fi

if [[ $faltou -eq 1 ]]; then
  echo ""
  echo "Resolva os itens marcados com [!!] e rode este script de novo." >&2
  exit 1
fi

# Aviso sobre a saida de rede: sem isso o QR code nunca aparece.
echo ""
echo -n "  Testando o acesso ao WhatsApp... "
if curl -sS -m 15 -o /dev/null -I https://web.whatsapp.com 2>/dev/null; then
  echo "ok"
else
  echo "FALHOU"
  echo ""
  echo "  AVISO: esta maquina nao alcanca web.whatsapp.com."
  echo "         Sem isso o QR code nao vai aparecer. Causas comuns:"
  echo "         firewall corporativo, VPN ou proxy bloqueando."
  echo ""
  read -r -p "  Continuar assim mesmo? [s/N] " segue
  [[ "$segue" == "s" || "$segue" == "S" ]] || exit 1
fi

# ------------------------------------------------------------------ .env
titulo "Passo 2 de 5 - Configurando"

if [[ -f "$ENV_FILE" ]]; then
  echo "  Ja existe um arquivo .env aqui."
  read -r -p "  Refazer a configuracao do zero? [s/N] " refaz
  if [[ "$refaz" != "s" && "$refaz" != "S" ]]; then
    echo "  Mantendo o .env atual."
    PULAR_ENV=1
  fi
fi

if [[ "${PULAR_ENV:-0}" != "1" ]]; then
  echo "  Escolha quem vai ser o cerebro do filtro:"
  echo ""
  echo "    1) Groq        - GRATIS, rapido        (recomendado)"
  echo "    2) Gemini      - GRATIS, do Google"
  echo "    3) OpenRouter  - GRATIS nos modelos :free"
  echo "    4) OpenAI      - PAGO"
  echo ""
  read -r -p "  Digite o numero [1]: " escolha
  escolha=${escolha:-1}

  case "$escolha" in
    1) PROVEDOR=groq;       LINK="https://console.groq.com/keys" ;;
    2) PROVEDOR=gemini;     LINK="https://aistudio.google.com/apikey" ;;
    3) PROVEDOR=openrouter; LINK="https://openrouter.ai/keys" ;;
    4) PROVEDOR=openai;     LINK="https://platform.openai.com/api-keys" ;;
    *) echo "  Opcao invalida." >&2; exit 1 ;;
  esac

  echo ""
  echo "  Pegue sua chave em: $LINK"
  echo "  (crie a conta, gere a chave e copie)"
  echo ""
  echo "  A chave NAO vai aparecer na tela enquanto voce cola - isso e de"
  echo "  proposito, para ela nao ficar no historico do terminal."
  echo ""

  CHAVE_IA=""
  while [[ -z "$CHAVE_IA" ]]; do
    # -s nao ecoa: a chave e uma credencial, nao deve ficar visivel nem no
    # scrollback nem em uma gravacao de tela.
    read -r -s -p "  Cole a chave aqui e aperte Enter: " CHAVE_IA
    echo ""
    if [[ -z "$CHAVE_IA" ]]; then
      echo "  A chave nao pode ficar vazia."
    else
      # Confirma que colou algo plausivel, sem revelar a chave.
      echo "  Recebi uma chave de ${#CHAVE_IA} caracteres (terminando em ...${CHAVE_IA: -4})."
    fi
  done

  # Chave da propria API: gerada sozinha, o usuario nao precisa inventar.
  if command -v openssl >/dev/null 2>&1; then
    CHAVE_API=$(openssl rand -hex 24)
  else
    CHAVE_API=$(python3 -c "import secrets; print(secrets.token_hex(24))")
  fi

  cp .env.docker.example "$ENV_FILE"
  python3 - "$ENV_FILE" "$CHAVE_API" "$CHAVE_IA" "$PROVEDOR" <<'PY'
import sys, re
arquivo, chave_api, chave_ia, provedor = sys.argv[1:5]
with open(arquivo) as f:
    texto = f.read()

def troca(chave, valor, texto):
    padrao = re.compile(r'^%s=.*$' % re.escape(chave), re.M)
    if padrao.search(texto):
        return padrao.sub('%s=%s' % (chave, valor), texto)
    return texto + '\n%s=%s\n' % (chave, valor)

texto = troca('AUTHENTICATION_API_KEY', chave_api, texto)
texto = troca('OPENAI_API_KEY_GLOBAL', chave_ia, texto)
texto = troca('AI_PROVIDER', provedor, texto)
with open(arquivo, 'w') as f:
    f.write(texto)
PY

  echo ""
  echo "  Configuracao salva em .env"
  echo "  A chave de acesso da sua API foi gerada automaticamente e esta"
  echo "  guardada no .env (o git ignora esse arquivo, nao vai para o GitHub)."
  echo ""
  echo "  Se precisar consultar depois:"
  echo "     grep AUTHENTICATION_API_KEY .env"
fi

# --------------------------------------------------------------- containers
titulo "Passo 3 de 5 - Subindo os servicos"
echo "  A primeira vez demora uns 5 minutos (esta compilando)."
echo "  Pode ir tomar um cafe."
echo ""

docker compose -f "$COMPOSE_FILE" up -d --build

echo ""
echo -n "  Esperando a API responder"
API_URL="http://localhost:8080"
no_ar=0
for _ in $(seq 1 90); do
  if curl -sSf -m 5 "$API_URL" >/dev/null 2>&1; then no_ar=1; break; fi
  printf "."
  sleep 2
done
echo ""

if [[ $no_ar -ne 1 ]]; then
  echo ""
  echo "  A API nao respondeu a tempo." >&2
  echo "  Veja o que aconteceu com:" >&2
  echo "     docker compose -f $COMPOSE_FILE logs -n 60 api" >&2
  exit 1
fi
echo "  API no ar."

# ------------------------------------------------------------------ whatsapp
titulo "Passo 4 de 5 - Conectando o seu WhatsApp"

echo "  Como voce prefere conectar?"
echo ""
echo "    1) QR code - voce le com a camera        (recomendado)"
echo "    2) Codigo de 8 digitos - voce digita no celular"
echo "       (use esta se estiver num servidor sem tela)"
echo ""
read -r -p "  Digite o numero [1]: " modo
modo=${modo:-1}

NUMERO=""
if [[ "$modo" == "2" ]]; then
  echo ""
  echo "  Digite o numero do WhatsApp que voce vai conectar,"
  echo "  com codigo do pais e DDD, so numeros."
  echo "  Exemplo: 5511987654321"
  echo ""
  read -r -p "  Numero: " NUMERO
  NUMERO=${NUMERO//[^0-9]/}
fi

echo ""
./whatsapp.sh connect "$NUMERO" || {
  echo ""
  echo "  A conexao nao completou. Voce pode tentar de novo com:" >&2
  echo "     ./whatsapp.sh connect" >&2
  echo ""
}

# -------------------------------------------------------------------- filtro
titulo "Passo 5 de 5 - Ligando o filtro de IA"
./setup-aifilter.sh

titulo "Tudo pronto"
cat <<'FIM'
  Teste agora: peca para alguem mandar uma mensagem no seu WhatsApp.

    "Oi, boa tarde!"            -> a IA responde sozinha
    "Voces abrem no sabado?"    -> a IA responde sozinha
    "Faz um desconto de 30%?"   -> a IA para e chama VOCE
    "GANHE R$ 5000 CLIQUE AQUI" -> ignorada

  Acompanhe o que esta acontecendo:

    ./monitor.sh              painel das conversas
    ./monitor.sh decisoes     o que a IA esta decidindo, ao vivo
    ./monitor.sh pausadas     quem esta esperando voce

  Responder alguem e devolver para a IA:

    ./monitor.sh responder 5511999999999 "minha resposta"
    ./monitor.sh reabrir 5511999999999

  Conexao do WhatsApp:

    ./whatsapp.sh status      ver se continua conectado
    ./whatsapp.sh logout      trocar de numero

  Para desligar tudo:  docker compose -f docker-compose.local.yaml down
FIM
echo ""
