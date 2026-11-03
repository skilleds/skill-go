#!/usr/bin/env bash
# check-index.sh — o gate DURO do indice de microfuncoes (secao 39).
#
# Motivo: A5 da vistoria de 2026-08-21 — o passo de CI rodava o gerador com `|| true` e o `diff`
# ficava COMENTADO, enquanto 5 lugares da normativa declaravam "o indice trava o merge". Gate
# declarado e desarmado e pior que gate ausente: da a garantia sem entregar.
# Entrada: $1 = diretorio de origem (default $INDEX_SRC) - $2 = indice commitado (default $INDEX_FILE).
# Saida: exit 0 indice em dia - exit 1 indice defasado, ausente ou parametro faltando.
# EXCEÇÃO DECLARADA de strict mode (`schematize-shell` -> `references/piso.md` secao 1):
# este script é um COLETOR — ele varre tudo e SOMA os achados. Com `set -e` abortaria no
# primeiro problema e reportaria um, escondendo os outros. Por isso `set -uo pipefail` sem `-e`.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:-${INDEX_SRC:-}}"
FILE="${2:-${INDEX_FILE:-}}"
GEN="${INDEX_GEN:-$HERE/build-index.mjs}"

[ -n "$SRC" ]  || { echo "✖ defina INDEX_SRC (diretorio de origem do indice)"; exit 1; }
[ -n "$FILE" ] || { echo "✖ defina INDEX_FILE (o indice commitado, ex: <projeto>_archive/index/INDEX_FUNCTIONS.md)"; exit 1; }
[ -d "$SRC" ]  || { echo "✖ origem nao existe: $SRC"; exit 1; }
[ -f "$FILE" ] || { echo "✖ indice commitado nao existe: $FILE"; exit 1; }

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
node "$GEN" "$SRC" > "$tmp"; gen_rc=$?
# O gerador sai 1 quando ha funcao sem doc-comment; isso tambem REPROVA (secao 6).
if [ "$gen_rc" -ne 0 ]; then
  echo "✖ gerador reprovou (rc=$gen_rc): ha unidade sem doc-comment de contexto (secao 6)"
  exit 1
fi
if diff -u "$FILE" "$tmp"; then
  echo "✔ indice em dia: $FILE"
  exit 0
fi
echo "✖ indice defasado (secao 39) — regenere e commite: node $GEN $SRC > $FILE"
exit 1
