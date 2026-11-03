#!/usr/bin/env bash
# EXCEÇÃO DECLARADA de strict mode (`schematize-shell` -> `references/piso.md` secao 1):
# este arquivo é uma BIBLIOTECA para `source` — ele NÃO liga `set -euo pipefail` de propósito.
# `set -e` num arquivo sourceado muda as opções do shell do CHAMADOR (ação à distância): o script
# que fizer `source lib.sh` passaria a abortar em lugares que ele não escolheu. Quem liga strict
# mode é o script; a biblioteca só oferece funções.
# shellcheck shell=bash
# lib.sh — helpers compartilhados da malha de testes <project>_ops.
# Source este arquivo no topo de todo script de teste:
#   source "$_DIR/lib.sh"
#
# Expõe: test_section, test_pass, test_fail, test_skip, test_summary,
#        http_call (popula HTTP_CODE / HTTP_BODY), assert_http_in, api_base.
# Contadores e TEST_EXIT_CODE são agregados por test_summary.

# --- cores (degradam pra vazio se não for TTY) -------------------------------
if [[ -t 1 ]]; then
  C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_YLW=$'\033[0;33m'
  C_BLU=$'\033[0;34m'; C_BLD=$'\033[1m';   C_RST=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_BLD=""; C_RST=""
fi

# --- contadores --------------------------------------------------------------
_PASS=0; _FAIL=0; _SKIP=0
TEST_EXIT_CODE=0

# --- config ------------------------------------------------------------------
# Resolve a base da API. Generalize <P>_TEST_API_BASE por projeto.
api_base() {
  echo "${API_BASE:-${PROJECT_TEST_API_BASE:-http://127.0.0.1:13000}}"
}

# --- saída -------------------------------------------------------------------
test_section() {
  echo
  echo "${C_BLU}${C_BLD}=== $* ===${C_RST}"
}

test_pass() {
  _PASS=$((_PASS+1))
  echo "  ${C_GRN}✓${C_RST} $1"
}

# test_fail "mensagem" ["corpo/evidência opcional"]
test_fail() {
  _FAIL=$((_FAIL+1))
  TEST_EXIT_CODE=1
  echo "  ${C_RED}✗ $1${C_RST}"
  if [[ -n "${2:-}" ]]; then
    # evidência truncada em 2000 chars, sem vazar PII além disso
    echo "${2}" | head -c 2000 | sed 's/^/      /'
    echo
  fi
}

test_skip() {
  _SKIP=$((_SKIP+1))
  echo "  ${C_YLW}○ skip${C_RST} $1"
}

# http_call METHOD URL [curl-args...]
# Popula HTTP_CODE e HTTP_BODY. Nunca usa "|| true" que esconde erro de rede:
# falha de conexão vira HTTP_CODE=000, que o chamador deve tratar como FAIL.
http_call() {
  local method="$1"; shift
  local url="$1"; shift
  local raw
  raw="$(curl -sS -m 15 -w $'\n__HTTP_CODE__%{http_code}' \
         -X "$method" "$url" "$@" 2>/dev/null)" || raw=$'\n__HTTP_CODE__000'
  HTTP_CODE="${raw##*__HTTP_CODE__}"
  HTTP_BODY="${raw%$'\n'__HTTP_CODE__*}"
}

# assert_http_in "descrição" "200|401|404" METHOD URL [curl-args...]
# Passa se o status retornado casa o regex de códigos esperados.
assert_http_in() {
  local desc="$1"; shift
  local expect="$1"; shift
  local method="$1"; shift
  local url="$1"; shift
  http_call "$method" "$url" "$@"
  if [[ "$HTTP_CODE" =~ ^($expect)$ ]]; then
    test_pass "$desc (HTTP $HTTP_CODE)"
  else
    test_fail "$desc — esperado [$expect], obtido $HTTP_CODE" "$HTTP_BODY"
  fi
}

# test_summary "<categoria>/<nome>" — banner ENORME em vermelho se houve falha.
test_summary() {
  local label="${1:-suite}"
  echo
  if [[ "$TEST_EXIT_CODE" -ne 0 ]]; then
    echo "${C_RED}${C_BLD}"
    echo "################################################################"
    echo "##  FALHA EM ${label}"
    echo "##  pass=${_PASS}  fail=${_FAIL}  skip=${_SKIP}"
    echo "################################################################"
    echo "${C_RST}"
  else
    echo "${C_GRN}${C_BLD}── OK ${label}  (pass=${_PASS} skip=${_SKIP}) ──${C_RST}"
  fi
}
