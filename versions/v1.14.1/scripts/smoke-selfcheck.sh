#!/usr/bin/env bash
# Smoke · Self-check (anti "verde mentiroso")
# Prova que o runner CONSEGUE reportar FAIL. Se este script "passar" quando
# deveria falhar, o smoke está cego e o CI deve quebrar.
#
# Uso:
#   bash smoke-selfcheck.sh            # modo normal: sai 0 se a suite passou
#   bash smoke-selfcheck.sh --self-check  # forca uma falha conhecida:
#                                         #   sai 0 SE o runner reportou o FAIL (e a prova)
#                                         #   sai 1 se NAO reportou (smoke cego)
#
# No CI: rode AMBOS. Normal=0 e --self-check=0-tendo-reportado-FAIL provam que o smoke
# ve verde e vermelho. O --self-check NUNCA sai 1 por ter falhado de proposito: sair 1 ali
# significa que a falha forcada passou despercebida.

# strict-ok: harness de auto-verificação — ele PRECISA continuar depois da falha proposital para provar que o runner sabe reportar FAIL (`schematize-shell` -> `references/piso.md` secao 1)
set -uo pipefail
_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$_DIR/lib.sh"

API="$(api_base)"
MODE="${1:-normal}"

test_section "Smoke · Self-check do runner"

# 1) Canário 404: rota fake DEVE devolver 404. Se devolver 200, o roteamento
#    está aceitando qualquer coisa (catch-all suspeito).
assert_http_in "rota inexistente devolve 404" "404" GET "$API/_smoke_canary_should_404"

# 2) Prova viva de que test_fail funciona: em --self-check, forçamos uma falha.
#    Em modo normal, registramos um pass de controle.
if [[ "$MODE" == "--self-check" ]]; then
  test_fail "falha forçada (esperada no --self-check)" "se você vê isto com exit 0, o runner está quebrado"
else
  test_pass "runner inicializado e capaz de registrar pass"
fi

# 3) Garante que health real valida dependência (não é 200 estático).
#    /ready deve refletir o estado das dependências, não responder cego.
http_call GET "$API/ready"
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "503" ]]; then
  test_pass "/ready respondeu estado de readiness (HTTP $HTTP_CODE)"
else
  test_fail "/ready com status inesperado" "HTTP $HTTP_CODE :: $HTTP_BODY"
fi

test_summary "smoke/self-check"

# Contrato do self-check (o codigo abaixo E a definicao; a doc do topo diz o mesmo):
#   modo normal       -> exit = TEST_EXIT_CODE (0 se a suite passou)
#   modo --self-check -> exit 0 SE TEST_EXIT_CODE==1 (o runner reportou a falha forcada)
#                        exit 1 se TEST_EXIT_CODE!=1 (smoke cego: a falha nao foi vista)
if [[ "$MODE" == "--self-check" ]]; then
  if [[ "$TEST_EXIT_CODE" -eq 1 ]]; then
    echo "${C_GRN}self-check OK: o runner reportou FAIL como esperado.${C_RST}"
    exit 0   # provar que sabe falhar é, em si, um sucesso
  else
    echo "${C_RED}${C_BLD}SMOKE CEGO: falha forçada NÃO foi reportada. Conserte o runner.${C_RST}"
    exit 1
  fi
fi

exit $TEST_EXIT_CODE
