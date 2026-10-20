#!/usr/bin/env bash
# <Categoria> · <Nome curto>
# Descrição clara do que cobre e o esperado.
# Esperado: status X em caso Y. Falha = significado Z.
#
# Skeleton obrigatório (ver a `schematize-qa` (padrao de script, `references/execucao.md` secao 3)). Copie para tests/<mode>/<name>.sh e preencha.
# Cada script é executável standalone e sai 0 (tudo passou) ou 1 (qualquer falha).

# strict-ok: harness de teste — roda TODOS os casos e soma; com `-e` pararia no primeiro vermelho e esconderia o resto (`schematize-shell` -> `references/piso.md` secao 1)
set -uo pipefail
_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib.sh
source "$_DIR/lib.sh"

test_section "<Categoria> · <Nome>"

API="$(api_base)"

# --- Caso 1: status esperado -------------------------------------------------
assert_http_in "<descrição do caso>" "200|401" GET "$API/v1/<rota>"

# --- Caso 2: shape do body (não basta status) --------------------------------
http_call GET "$API/v1/<rota>"
if [[ "$HTTP_CODE" == "200" ]]; then
  if echo "$HTTP_BODY" | jq -e '.data | length > 0' >/dev/null 2>&1; then
    test_pass "<rota> retorna dados"
  else
    test_fail "<rota> sem 'data'" "$HTTP_BODY"
  fi
fi

# --- Caso 3: assertion negativa (o que NÃO pode estar lá) --------------------
if echo "$HTTP_BODY" | grep -qiE 'stacktrace|exception|undefined|\{\{|\$\{'; then
  test_fail "<rota> vazou stack trace / placeholder não renderizado" "$HTTP_BODY"
else
  test_pass "<rota> sem vazamento de erro"
fi

test_summary "<categoria>/<nome>"
exit $TEST_EXIT_CODE
