#!/usr/bin/env bash
# check-diff.sh — gate determinístico de padrões (§6, §35, §37) sobre o diff.
# Uso: bash scripts/check-diff.sh [base-ref]   (default: origin/main)
# Sai 1 se achar qualquer violação de PISO; imprime achados com arquivo:linha.
#
# Cobre o que dá pra checar por regex/contagem. O julgamento fino (semântica de
# auth, coerção de tipo, etc.) fica pro /go-review com leitura humana/da IA.

# EXCEÇÃO DECLARADA de strict mode (`schematize-shell` -> `references/piso.md` secao 1):
# este script é um COLETOR — ele varre tudo e SOMA os achados. Com `set -e` abortaria no
# primeiro problema e reportaria um, escondendo os outros. Por isso `set -uo pipefail` sem `-e`.
set -uo pipefail
BASE="${1:-origin/main}"
FAIL=0
RED=$'\033[0;31m'; YLW=$'\033[0;33m'; GRN=$'\033[0;32m'; RST=$'\033[0m'

# Base inexistente NAO pode virar verde: `git diff` falha, FILES fica vazio e o gate diria OK sem ter olhado nada.
if ! git rev-parse --verify -q "$BASE^{commit}" >/dev/null 2>&1; then
  echo "${RED}✗ BLOQUEIA${RST} base '$BASE' não resolve para um commit (ou não é repo git) — o gate não olhou nada"
  exit 1
fi

# Arquivos de código alterados (exclui exceções da §6).
mapfile -t FILES < <(git diff --name-only "$BASE"...HEAD 2>/dev/null \
  | grep -E '\.(go|rs|ts|tsx|js|mjs|jsx)$' \
  | grep -vE '(_test\.|\.test\.|/migrations/|/generated/|\.gen\.|/mocks?/)' || true)

block() { echo "${RED}✗ BLOQUEIA${RST} $1"; FAIL=1; }
warn()  { echo "${YLW}⚠ ATENÇÃO${RST} $1"; }

echo "== schematize-go check-diff (base: $BASE) =="

# 1) §6 — tamanho de arquivo em camadas: teto DURO 750 (≤500 útil + ~250 comentário),
#    FLAG (não bloqueia) em >300 de código útil (~400 em observabilidade).
useful_lines() { # conta linhas de código útil: exclui branco e linha só-comentário (aprox multi-linguagem)
  grep -vcE '^[[:space:]]*($|//|#|///|/\*|\*/|\*[^/])' "$1" 2>/dev/null || echo 0
}
is_observ() { echo "$1" | grep -qiE '(observ|telemetr|tracing|/metrics?|metric|instrument|logg?(er|ing)|otel|prometheus|opentelemetry)'; }
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  total=$(wc -l < "$f"); useful=$(useful_lines "$f")
  if (( total > 750 )); then
    block "$f: $total linhas (>750 teto duro; ~250 são p/ comentário, ~500 úteis) — quebre por coesão (§6)"
  elif (( useful > 500 )); then
    block "$f: $useful linhas de código útil (>500 teto duro) — quebre por coesão (§6)"
  else
    thr=300; ctx=""
    is_observ "$f" && { thr=400; ctx=" [observabilidade infla ~400]"; }
    (( useful > thr )) && warn "$f: $useful linhas de código útil (>$thr)$ctx — indício de função muito extensa / falta de abstração; FLAG, registre como dívida p/ rever quando prioridades permitirem (§6)"
  fi
done

# 2) §37 — macaquices grep-áveis (padrão -> mensagem)
# scan "regex" "mensagem" [--perl]
#   Roda a regex sobre os arquivos do diff e BLOQUEIA em cada acerto.
#   O `|| true` de antes engolia o exit 2 do grep (regex invalida / erro de I/O) e transformava
#   ERRO DE REGEX EM VERDE — foi assim que o piso de `<img>` sem alt ficou morto desde que existe
#   (A3/A3b da vistoria de 2026-08-21). Agora: 0 = achou, 1 = nao achou, >=2 = ERRO, e erro FALHA.
scan() {
  local re="$1" msg="$2" flavor="${3:-ere}" hit rc
  local -a gflags
  case "$flavor" in
    --perl|perl) gflags=(-nP) ;;
    *)           gflags=(-nE) ;;
  esac
  for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || continue
    hit=$(grep "${gflags[@]}" "$re" "$f" 2>/dev/null); rc=$?
    if (( rc >= 2 )); then
      block "scripts/check-diff.sh — grep saiu $rc na regra '"'"'$msg'"'"' (regex invalida ou arquivo ilegivel): $re"
      continue
    fi
    (( rc == 0 )) && while IFS= read -r l; do block "$f:${l%%:*} — $msg"; done <<< "$hit"
  done
}

# has_perl_grep — `grep -P` existe nesta maquina? Sem ele, regra que exige lookahead NAO roda
# em silencio; entao a ausencia vira BLOQUEIO explicito, nao um verde a menos.
has_perl_grep() { echo x | grep -qP x 2>/dev/null; }
scan 'NEXT_PUBLIC_[A-Z_]*(SECRET|KEY|TOKEN|PASSWORD|PRIVATE)' 'segredo exposto via NEXT_PUBLIC_ (§13.4/§37)'
scan 'rejectUnauthorized:\s*false|InsecureSkipVerify:\s*true|verify\s*=\s*False' 'verificação TLS desabilitada (§37)'
scan 'Math\.random\(\).*(token|secret|session|nonce|reset)' 'Math.random em contexto de segredo — use CSPRNG (§14/§37)'
scan 'eslint-disable.*security|//\s*nolint:.*(gosec|sec)|#\s*nosec' 'desabilitando regra de segurança inline (§37)'
scan 'Access-Control-Allow-Origin["'\'' :,]*\*' 'CORS * — allowlist explícita (§37)'
scan '(query|exec|raw)\(\s*[`"'\''].*\$\{|"\s*\+\s*.*(req|input|param|body)' 'possível SQL/comando por concatenação (§10/§37)'
scan 'catch\s*\(\s*\)\s*\{\s*\}|except\s*:\s*pass|catch\s*\{\s*\}' 'erro engolido (§37)'
scan '@ts-ignore|: any\b|interface\{\}' 'tipo silenciado (any/@ts-ignore/interface{}) (§37)'
scan '\.(skip|only)\(|t\.Skip\(|xit\(|@Ignore' 'teste pulado/silenciado (§37)'

# 3) §39 — índice atualizado quando muda funcionalidade
if (( ${#FILES[@]} > 0 )); then
  idx=$(git diff --name-only "$BASE"...HEAD 2>/dev/null | grep -E 'INDEX_(GLOBAL|FUNCTIONS)\.md' || true)
  [[ -z "$idx" ]] && warn "diff mexe em código mas não toca INDEX_*.md — índice atualizado? (§39)"
fi

# 4) §3 — backend novo em PHP
php=$(git diff --name-only "$BASE"...HEAD 2>/dev/null | grep -E '\.php$' || true)
[[ -n "$php" ]] && block "arquivo PHP no diff — PHP é proibido, migrar (§3.2): $php"

echo
if (( FAIL )); then
  echo "${RED}== check-diff: BLOQUEADO ==${RST}"; exit 1
else
  echo "${GRN}== check-diff: OK ==${RST}"; exit 0
fi
