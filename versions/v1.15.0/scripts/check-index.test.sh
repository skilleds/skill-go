#!/usr/bin/env bash
# check-index.test.sh — o VERMELHO VISTO do gate do indice (A5 da vistoria de 2026-08-21).
#
# Motivo: o passo de CI rodava `build-index.mjs ... || true` com o `diff` COMENTADO, enquanto
# 5 lugares da normativa diziam que "o indice trava o merge". Este teste exige que o gate
# reprove com indice defasado, ausente e sem parametro; e que passe com indice em dia.
# Entrada: nenhuma. Saida: exit 0 todos os casos passam - exit 1 algum caso falhou.
# EXCEÇÃO DECLARADA de strict mode (`schematize-shell` -> `references/piso.md` secao 1):
# harness de teste roda sem `-e` de propósito — ele precisa continuar depois de um caso
# vermelho para reportar TODOS, em vez de parar no primeiro.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
rc=0
mkdir -p "$W/src"
cat > "$W/src/a.mjs" <<'JS'
/** O quê: soma dois numeros. Onde: usado pelo relatorio. */
export function soma(a, b) { return a + b; }
JS

echo "── indice EM DIA passa"
node "$HERE/build-index.mjs" "$W/src" > "$W/INDEX.md" 2>/dev/null
OUT=$(INDEX_SRC="$W/src" INDEX_FILE="$W/INDEX.md" bash "$HERE/check-index.sh" 2>&1); z=$?
if [ "$z" -eq 0 ]; then echo "  ✔ exit 0"; else echo "  ✖ exit $z: $OUT"; rc=1; fi

echo "── indice DEFASADO reprova (o caso que o '|| true' engolia)"
cat >> "$W/src/a.mjs" <<'JS'
/** O quê: subtrai dois numeros. Onde: usado pelo relatorio. */
export function subtrai(a, b) { return a - b; }
JS
OUT=$(INDEX_SRC="$W/src" INDEX_FILE="$W/INDEX.md" bash "$HERE/check-index.sh" 2>&1); z=$?
if [ "$z" -eq 1 ] && grep -q 'defasado' <<<"$OUT"; then echo "  ✔ exit 1 e 'indice defasado'"; else echo "  ✖ exit $z: $OUT"; rc=1; fi

echo "── funcao SEM doc-comment reprova (secao 6)"
printf 'export function semDoc(x) { return x; }\n' > "$W/src/b.mjs"
node "$HERE/build-index.mjs" "$W/src" > "$W/INDEX.md" 2>/dev/null
OUT=$(INDEX_SRC="$W/src" INDEX_FILE="$W/INDEX.md" bash "$HERE/check-index.sh" 2>&1); z=$?
if [ "$z" -eq 1 ] && grep -q 'doc-comment' <<<"$OUT"; then echo "  ✔ exit 1 e 'sem doc-comment'"; else echo "  ✖ exit $z: $OUT"; rc=1; fi

echo "── parametro AUSENTE reprova (nao roda != passa)"
OUT=$(bash "$HERE/check-index.sh" 2>&1); z=$?
if [ "$z" -eq 1 ] && grep -q 'INDEX_SRC' <<<"$OUT"; then echo "  ✔ exit 1 e pede INDEX_SRC"; else echo "  ✖ exit $z: $OUT"; rc=1; fi
OUT=$(INDEX_SRC="$W/src" bash "$HERE/check-index.sh" 2>&1); z=$?
if [ "$z" -eq 1 ] && grep -q 'INDEX_FILE' <<<"$OUT"; then echo "  ✔ exit 1 e pede INDEX_FILE"; else echo "  ✖ exit $z: $OUT"; rc=1; fi

echo "── indice commitado AUSENTE reprova"
OUT=$(INDEX_SRC="$W/src" INDEX_FILE="$W/nao-existe.md" bash "$HERE/check-index.sh" 2>&1); z=$?
if [ "$z" -eq 1 ] && grep -q 'nao existe' <<<"$OUT"; then echo "  ✔ exit 1"; else echo "  ✖ exit $z: $OUT"; rc=1; fi

echo
[ $rc -eq 0 ] && echo "✔ check-index.test.sh: todos os casos" || echo "✖ check-index.test.sh: falhou"
exit $rc
