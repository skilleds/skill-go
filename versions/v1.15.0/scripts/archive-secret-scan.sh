#!/usr/bin/env bash
# archive-secret-scan.sh — varre os MDs do archive em busca de segredo/PII antes
# do commit. Os handoffs/checklists/planos são gerados automaticamente e podem
# capturar segredo sem querer; isto protege contra violar §16.1/§32.
#
# Uso (pre-commit): bash scripts/archive-secret-scan.sh [dir]   (default: o diretorio atual)
# O alvo e o `<projeto>/<projeto>_archive/` — a convencao `<projeto>/_archive` foi REVOGADA
# na v0.19.0; a planta canonica esta na schematize-archive (references/archive.md, ADR-0005).
# Sai 1 se achar candidato a segredo/PII. Usa gitleaks se disponível; senão regex.

# strict-ok: coletor — varre tudo e soma os achados; `grep` sem match sai 1 e é resultado normal aqui, não erro (`schematize-shell` -> `references/piso.md` secao 1)
set -uo pipefail
DIR="${1:-${PROJECT_ARCHIVE_ROOT:-.}}"
RED=$'\033[0;31m'; GRN=$'\033[0;32m'; RST=$'\033[0m'

# Só arquivos do archive (ajuste o glob ao seu layout).
mapfile -t MDS < <(find "$DIR" -type f \( -name '*.md' -o -name '*.jsonl' \) \
  -path '*_archive/*' 2>/dev/null || true)
(( ${#MDS[@]} == 0 )) && { echo "${GRN}archive-secret-scan: nada a varrer.${RST}"; exit 0; }

if command -v gitleaks >/dev/null 2>&1; then
  echo "== gitleaks no archive =="
  gitleaks detect --no-git --source "$DIR" --redact && { echo "${GRN}OK${RST}"; exit 0; } || { echo "${RED}segredo detectado no archive${RST}"; exit 1; }
fi

echo "== scan regex (gitleaks ausente) =="
FAIL=0
# padrões de segredo/PII comuns (chaves, JWT, bearer, CPF, email em massa, cartão)
PAT='(AKIA[0-9A-Z]{16})|(sk-[A-Za-z0-9]{20,})|(ghp_[A-Za-z0-9]{36})|(eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})|(-----BEGIN [A-Z ]*PRIVATE KEY-----)|([Bb]earer\s+[A-Za-z0-9._-]{20,})|(password["'\'' :=]+[^ "'\'']{6,})|([0-9]{3}\.[0-9]{3}\.[0-9]{3}-[0-9]{2})'
for f in "${MDS[@]}"; do
  hit=$(grep -nE "$PAT" "$f" 2>/dev/null || true)
  if [[ -n "$hit" ]]; then
    echo "${RED}✗ candidato a segredo/PII em $f${RST}"
    echo "$hit" | sed 's/\(.\{12\}\).*/\1…(redigido)/' | head -5 | sed 's/^/   /'
    FAIL=1
  fi
done
if (( FAIL )); then
  echo "${RED}== archive-secret-scan: BLOQUEADO — remova o segredo do MD (§16.1/§32) ==${RST}"; exit 1
fi
echo "${GRN}== archive-secret-scan: OK ==${RST}"; exit 0
