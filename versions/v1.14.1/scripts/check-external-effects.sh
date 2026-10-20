#!/usr/bin/env bash
# herdado de schematize-engineering — não edite aqui (fonte: skill-engineering/scripts/check-external-effects.sh; regenere: node tools/sync-herdados.mjs)
# check-external-effects.sh — gate determinístico do piso "efeito externo NUNCA sai de
# não-produção" (SKILL.md; normativa em `schematize-engineering` -> references/efeitos-externos.md;
# anti-padrão §37 "Disparar efeito externo REAL a partir de não-produção" — citado por TÍTULO,
# porque a numeração do §37 diverge entre skills).
#
# Este arquivo é DISTRIBUÍDO IDÊNTICO a toda skill que declara o piso: instalar só a skill de
# linguagem (sem a base) não pode deixar o projeto sem o gate. Até 2026-08-21 ele existia em
# UM lugar só e o piso vivia como prosa nas outras — o agravante registrado na vistoria.
#
# Uso:  bash scripts/check-external-effects.sh [dir]            (default: .)
#       TEST_MAIL_DOMAIN=test.exemplo.com bash scripts/check-external-effects.sh
#
# Sai 1 se achar:
#   1) endereço de e-mail em domínio de terceiro/pessoa real em test/seed/fixture/persona;
#   2) chave de provedor de envio (Resend/SES/Twilio/SendGrid/Postmark/Mailgun) em .env
#      de dev/hml que NÃO seja sandbox;
#   3) ausência de cap de envio por execução na config;
#   4) (se `dig` existir e TEST_MAIL_DOMAIN estiver setado) domínio de teste SEM null MX.
#
# O que ele NÃO faz: julgar semântica do provider (isso é revisão). Aqui é o que
# regex e DNS provam sozinhos — o suficiente pra travar o acidente das 5.000 mensagens.

# EXCEÇÃO DECLARADA de strict mode (`schematize-shell` -> `references/piso.md` secao 1):
# este script é um COLETOR — ele varre tudo e SOMA os achados. Com `set -e` abortaria no
# primeiro problema e reportaria um, escondendo os outros. Por isso `set -uo pipefail` sem `-e`.
set -uo pipefail
DIR="${1:-.}"
FAIL=0
RED=$'\033[0;31m'; YLW=$'\033[0;33m'; GRN=$'\033[0;32m'; RST=$'\033[0m'
block() { echo "${RED}✗ BLOQUEIA${RST} $1"; FAIL=1; }
warn()  { echo "${YLW}⚠ ATENÇÃO${RST} $1"; }

echo "== check-external-effects (dir: $DIR) =="

# ---------------------------------------------------------------- 1) destinatário real
# Domínios de caixa real: qualquer um deles num artefato de teste é e-mail de verdade
# esperando ser enviado. A lista cobre os provedores de massa; domínio de cliente é
# pego pela revisão (regex não adivinha).
REAIS='gmail\.com|googlemail\.com|hotmail\.com|outlook\.com|live\.com|msn\.com|yahoo\.com(\.br)?|icloud\.com|me\.com|proton(mail)?\.(me|com|ch)|aol\.com|uol\.com\.br|bol\.com\.br|terra\.com\.br|globo\.com|zoho\.com|yandex\.(ru|com)|gmx\.(com|net|de)|mail\.ru|qq\.com|163\.com'

mapfile -t ALVOS < <(find "$DIR" -type f \
  \( -path '*test*' -o -path '*Test*' -o -path '*spec*' -o -path '*seed*' -o -path '*Seed*' \
     -o -path '*fixture*' -o -path '*factor*' -o -path '*persona*' -o -path '*mock*' \
     -o -path '*demo*' -o -path '*sample*' -o -name '*_test.*' -o -name '*.test.*' \
     -o -name '*.spec.*' -o -name '*.sql' -o -name '*.env*' \) \
  -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/target/*' \
  -not -path '*/vendor/*' -not -path '*/dist/*' -not -path '*/.next/*' 2>/dev/null || true)

if (( ${#ALVOS[@]} > 0 )); then
  HITS=$(grep -nEI "[[:alnum:]._%+-]+@($REAIS)" "${ALVOS[@]}" 2>/dev/null || true)
  if [[ -n "$HITS" ]]; then
    block "endereço de e-mail em domínio de caixa REAL em artefato de teste/seed/fixture:"
    echo "$HITS" | sed 's/^/    /' | head -40
    echo "    → troque pelo domínio de teste em ROTA NULA (\$TEST_MAIL_DOMAIN, null MX)"
    echo "      ou por TLD reservado (.test/.invalid/.example) — references/efeitos-externos.md"
  fi
fi

# ---------------------------------------------------------- 2) chave de prd em não-prd
mapfile -t ENVS < <(find "$DIR" -type f -name '.env*' -not -path '*/.git/*' \
  -not -path '*/node_modules/*' 2>/dev/null | grep -viE '\.(example|sample|template)$' || true)
for e in "${ENVS[@]:-}"; do
  [[ -f "$e" ]] || continue
  # Ambiente declarado no próprio arquivo; sem declaração, assume não-prd (fail-closed).
  ENVV=$(grep -ioE '^[[:space:]]*(APP_)?(ENV|ENVIRONMENT|NODE_ENV|RAILS_ENV|MIX_ENV)[[:space:]]*=[[:space:]]*[a-z]+' "$e" 2>/dev/null \
         | head -1 | sed 's/.*=//' | tr -d ' "'"'"'' | tr 'A-Z' 'a-z')
  case "$ENVV" in prd|prod|production) continue;; esac
  CHAVE=$(grep -nE '^[[:space:]]*(RESEND_API_KEY|SENDGRID_API_KEY|POSTMARK_[A-Z_]*TOKEN|MAILGUN_API_KEY|TWILIO_AUTH_TOKEN|AWS_SES_[A-Z_]+|SMTP_PASS(WORD)?)[[:space:]]*=[[:space:]]*[^[:space:]]' "$e" 2>/dev/null \
           | grep -viE '(sandbox|test|dummy|changeme|placeholder|xxx|=[[:space:]]*$)' || true)
  if [[ -n "$CHAVE" ]]; then
    block "credencial de provedor de envio em ambiente NÃO-produtivo ($e, env='${ENVV:-indefinido}'):"
    echo "$CHAVE" | sed 's/=.*/=<redigido>/' | sed 's/^/    /'
    echo "    → em não-prd o provider default é o SINK; se precisar de chave, que seja a SANDBOX."
  fi
  # 3) cap por execução declarado?
  if grep -qiE '(RESEND|SENDGRID|POSTMARK|MAILGUN|TWILIO|SMTP)' "$e" 2>/dev/null \
     && ! grep -qiE '(MAIL_MAX_PER_RUN|MAX_EMAILS_PER_RUN|MAIL_SEND_CAP)' "$e" 2>/dev/null; then
    warn "$e configura envio mas não declara cap por execução (MAIL_MAX_PER_RUN) — sem teto, 1 laço vira 5.000 mensagens."
  fi
done

# ------------------------------------------------------------------ 4) null MX de fato
if [[ -n "${TEST_MAIL_DOMAIN:-}" ]] && command -v dig >/dev/null 2>&1; then
  MX=$(dig +short MX "$TEST_MAIL_DOMAIN" 2>/dev/null | tr -d ' ' || true)
  if [[ -z "$MX" ]]; then
    warn "TEST_MAIL_DOMAIN=$TEST_MAIL_DOMAIN não tem MX publicado (sem MX ≠ null MX explícito; publique 'MX 0 .')."
  elif [[ "$MX" != "0." ]]; then
    block "TEST_MAIL_DOMAIN=$TEST_MAIL_DOMAIN NÃO está em rota nula — MX='$MX' (esperado '0 .', RFC 7505)."
  else
    echo "${GRN}✓${RST} $TEST_MAIL_DOMAIN em rota nula (null MX)."
  fi
  SPF=$(dig +short TXT "$TEST_MAIL_DOMAIN" 2>/dev/null | grep -i 'v=spf1' || true)
  [[ "$SPF" == *'-all'* ]] || warn "$TEST_MAIL_DOMAIN sem SPF '-all' (esperado 'v=spf1 -all')."
fi

if (( FAIL )); then
  echo "${RED}== FALHOU: efeito externo pode escapar de não-produção. ==${RST}"
  echo "Piso: schematize-engineering -> references/efeitos-externos.md"
  echo "      anti-padrão §37 'Disparar efeito externo REAL a partir de não-produção'."
  exit 1
fi
echo "${GRN}== OK: nenhum efeito externo real detectado fora de produção. ==${RST}"
