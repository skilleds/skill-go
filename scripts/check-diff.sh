#!/usr/bin/env bash
# check-diff.sh — gate determinístico de padrões (§6, §35, §37) sobre o diff.
# Uso: bash scripts/check-diff.sh [--staged | base-ref] [--allow-empty]
#   --staged   olha o que está no INDEX (git diff --cached) — é o modo do hook de pre-commit.
#   base-ref   olha base...HEAD (default: origin/main); em CI de promoção use a última tag hml-*/v*.
#   Base que resolve para o próprio HEAD dá diff VAZIO (falso verde): BLOQUEIA, salvo --allow-empty.
# Sai 1 se achar qualquer violação de PISO; imprime achados com arquivo:linha.
#
# Cobre o que dá pra checar por regex/contagem. O julgamento fino (semântica de
# auth, coerção de tipo, etc.) fica pro /go-review com leitura humana/da IA.

# EXCEÇÃO DECLARADA de strict mode (`schematize-shell` -> `references/piso.md` secao 1):
# este script é um COLETOR — ele varre tudo e SOMA os achados. Com `set -e` abortaria no
# primeiro problema e reportaria um, escondendo os outros. Por isso `set -uo pipefail` sem `-e`.
set -uo pipefail
STAGED=0; ALLOW_EMPTY=0; BASE=""
for a in "$@"; do
  case "$a" in
    --staged) STAGED=1 ;;
    --allow-empty) ALLOW_EMPTY=1 ;;
    -*) echo "uso: check-diff.sh [--staged | base-ref] [--allow-empty]" >&2; exit 2 ;;
    *) BASE="$a" ;;
  esac
done
BASE="${BASE:-origin/main}"
FAIL=0
TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
RED=$'\033[0;31m'; YLW=$'\033[0;33m'; GRN=$'\033[0;32m'; RST=$'\033[0m'

# Base inexistente NAO pode virar verde: `git diff` falha, FILES fica vazio e o gate diria OK sem ter olhado nada.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "${RED}✗ BLOQUEIA${RST} não é um repo git — o gate não olhou nada"
  exit 1
fi
if (( STAGED )); then
  LABEL="staged"
else
  LABEL="$BASE"
  if ! git rev-parse --verify -q "$BASE^{commit}" >/dev/null 2>&1; then
    echo "${RED}✗ BLOQUEIA${RST} base '$BASE' não resolve para um commit — o gate não olhou nada"
    exit 1
  fi
  # base == HEAD => `base...HEAD` é SEMPRE vazio: era o falso verde permanente do hook `check-diff.sh HEAD`.
  if [[ "$(git rev-parse "$BASE^{commit}")" == "$(git rev-parse HEAD)" ]] && (( ! ALLOW_EMPTY )); then
    echo "${RED}✗ BLOQUEIA${RST} base '$BASE' é o próprio HEAD — diff vazio, o gate não olhou nada (no pre-commit use --staged)"
    exit 1
  fi
fi

# Nomes alterados: no INDEX (--staged) ou base...HEAD.
changed_names() {
  if (( STAGED )); then git diff --cached --name-only --diff-filter=ACMR 2>/dev/null
  else git diff --name-only "$BASE"...HEAD 2>/dev/null; fi
}
# Arquivos de código alterados, SEM migrations/generated/mocks. CHANGED inclui os de teste
# (regras de silenciamento de teste precisam deles); FILES é o código de produção (exceções da §6).
mapfile -t CHANGED < <(changed_names \
  | grep -E '\.(go|rs|ts|tsx|js|mjs|jsx)$' \
  | grep -vE '(/migrations/|/generated/|\.gen\.|/mocks?/)' || true)
mapfile -t FILES < <(printf '%s\n' "${CHANGED[@]}" \
  | grep -vE '(_test\.|\.test\.|\.spec\.|/tests?/|/tests\.rs$|/__tests__/)' || true)

# prod_view FILE — em .rs, só a parte de PRODUÇÃO: corta do primeiro `#[cfg(test)]` até o fim
# (convenção: `mod tests` no FIM do arquivo). Testes inline não contam no teto de linhas nem
# disparam unwrap/expect. Prefixo do arquivo => os números de linha continuam válidos.
prod_view() {
  local f="$1" out="$TMPD/v$RANDOM$RANDOM"
  if [[ "$f" == *.rs ]]; then
    awk '/^[[:space:]]*#\[cfg\(test\)\]/{exit} {print}' "$f" > "$out"; echo "$out"
  else
    echo "$f"
  fi
}

block() { echo "${RED}✗ BLOQUEIA${RST} $1"; FAIL=1; }
warn()  { echo "${YLW}⚠ ATENÇÃO${RST} $1"; }

echo "== schematize-go check-diff (base: $LABEL) =="

# 1) §6 — tamanho de arquivo em camadas: teto DURO 750 (≤500 útil + ~250 comentário),
#    FLAG (não bloqueia) em >300 de código útil (~400 em observabilidade).
useful_lines() { # conta linhas de código útil: exclui branco e linha só-comentário (aprox multi-linguagem)
  # `#[attr]`/`#![attr]` (Rust) e `*x = ...` (deref) são CÓDIGO; `#` de shell/py e `//`, `/*`, ` * ` são comentário.
  grep -vcE '^[[:space:]]*($|//|#[^[!]|#$|/\*|\*/|\*[[:space:]]|\*$)' "$1" 2>/dev/null || echo 0
}
is_observ() { echo "$1" | grep -qiE '(observ|telemetr|tracing|/metrics?|metric|instrument|logg?(er|ing)|otel|prometheus|opentelemetry)'; }
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  v="$(prod_view "$f")"
  total=$(wc -l < "$v"); useful=$(useful_lines "$v")
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
# scan "regex" "mensagem" [flavor] [scope] [ext] [allow]
#   flavor: ere (default) | ere-i (sem caixa) | perl.   scope: code (default, só produção) | all (inclui testes).
#   ext: regex de extensão sobre o NOME do arquivo (default: todos).  allow=1: a linha com
#   `check-diff:allow: <motivo>` (≥5 chars) é aceita — escape VISÍVEL no diff, só p/ regras de linguagem.
#   Roda a regex sobre os arquivos do diff e BLOQUEIA em cada acerto.
#   O `|| true` de antes engolia o exit 2 do grep (regex invalida / erro de I/O) e transformava
#   ERRO DE REGEX EM VERDE — foi assim que o piso de `<img>` sem alt ficou morto desde que existe
#   (A3/A3b da vistoria de 2026-08-21). Agora: 0 = achou, 1 = nao achou, >=2 = ERRO, e erro FALHA.
scan() {
  local re="$1" msg="$2" flavor="${3:-ere}" scope="${4:-code}" ext="${5:-.}" allow="${6:-0}" hit rc src f
  local -a gflags set
  case "$flavor" in
    --perl|perl) gflags=(-nP) ;;
    ere-i)       gflags=(-niE) ;;
    *)           gflags=(-nE) ;;
  esac
  if [[ "$scope" == all ]]; then set=("${CHANGED[@]}"); else set=("${FILES[@]}"); fi
  for f in "${set[@]}"; do
    [[ -f "$f" ]] || continue
    [[ "$f" =~ $ext ]] || continue
    src="$f"; [[ "$scope" != all ]] && src="$(prod_view "$f")"
    hit=$(grep "${gflags[@]}" "$re" "$src" 2>/dev/null); rc=$?
    if (( rc >= 2 )); then
      block "scripts/check-diff.sh — grep saiu $rc na regra '"'"'$msg'"'"' (regex invalida ou arquivo ilegivel): $re"
      continue
    fi
    if (( rc == 0 && allow )); then
      hit=$(grep -vE 'check-diff:allow: .{5,}' <<<"$hit" || true)
    fi
    [[ -n "$hit" ]] && while IFS= read -r l; do block "$f:${l%%:*} — $msg"; done <<< "$hit"
  done
  return 0
}

# scan_both RE1 RE2 msg ext — bloqueia o ARQUIVO que casa as duas regex (ex.: math/rand + token).
scan_both() {
  local re1="$1" re2="$2" msg="$3" ext="$4" f src
  for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || continue
    [[ "$f" =~ $ext ]] || continue
    src="$(prod_view "$f")"
    if grep -qE "$re1" "$src" 2>/dev/null && grep -qiE "$re2" "$src" 2>/dev/null; then block "$f — $msg"; fi
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

# 2b) §37 — teste silenciado: roda TAMBÉM nos arquivos de teste (é onde o silenciamento mora).
scan '\.(skip|only)\(|xit\(|@Ignore' 'teste pulado/silenciado (§37)' ere all '\.(ts|tsx|js|mjs|jsx)$'
scan 't\.(Skip|SkipNow|Skipf)\(' 't.Skip — teste pulado para passar o CI; conserte o código/teste (§37)' ere all '\.go$' 1
scan '#\[ignore\b' '#[ignore] — teste silenciado para passar o CI; conserte o código/teste (§37)' ere all '\.rs$' 1

# 2c) vetos de LINGUAGEM (SKILL.md "Pisos inegociáveis") — por extensão. Escape: `// check-diff:allow: <motivo>`.
# Rust (só produção; `#[cfg(test)] mod tests` no fim do arquivo é ignorado)
scan '\.unwrap\(\)|\.expect\(' 'unwrap()/expect() em produção — trate o Result/Option (`?`, match, erro tipado) (§37)' ere code '\.rs$' 1
scan '(^|[^[:alnum:]_])let[[:space:]]+_[[:space:]]*(:[^=]+)?=' 'let _ = descarta resultado — erro engolido (§37)' ere code '\.rs$' 1
scan 'format!\(.*(SELECT |INSERT INTO|UPDATE .* SET|DELETE FROM)' 'SQL montado com format! — use binds do sqlx (§10/§37)' ere code '\.rs$' 1
# Go (só produção)
scan '(^|[;{[:space:]])_[[:space:]]*=[[:space:]]*err[[:space:]]*($|;|\})' '_ = err — erro engolido (§37)' ere code '\.go$' 1
scan '//[[:space:]]*nolint(:[A-Za-z0-9,_-]+)?[[:space:]]*$' '//nolint sem justificativa (§37)' ere code '\.go$' 1
scan '\bpanic\(' 'panic fora de main/init — devolva error (§37)' ere code '\.go$' 1
scan_both '"math/rand(/v2)?"' '(token|secret|session|nonce|otp|reset|password|senha)' 'math/rand em arquivo que lida com segredo/token/sessão — use crypto/rand (§14/§37)' '\.go$'


# 3) §39 — índice atualizado quando muda funcionalidade
if (( ${#FILES[@]} > 0 )); then
  idx=$(changed_names | grep -E 'INDEX_(GLOBAL|FUNCTIONS)\.md' || true)
  [[ -z "$idx" ]] && warn "diff mexe em código mas não toca INDEX_*.md — índice atualizado? (§39)"
fi

# 4) §3 — backend novo em PHP
php=$(changed_names | grep -E '\.php$' || true)
[[ -n "$php" ]] && block "arquivo PHP no diff — PHP é proibido, migrar (§3.2): $php"

echo
if (( FAIL )); then
  echo "${RED}== check-diff: BLOQUEADO ==${RST}"; exit 1
else
  echo "${GRN}== check-diff: OK ==${RST}"; exit 0
fi
