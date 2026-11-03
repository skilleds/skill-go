#!/usr/bin/env bash
# iam-guard.test.sh — compila e roda os exemplos de código do guard de e-mail (references/iam.md §3.1).
# O quê: extrai os blocos ```go da §3.1 (porta+erros, sink+resend, guard, testes), monta um módulo
#   temporário (mktemp) e roda `go vet` + `go test -race`. Se alguém editar o exemplo e quebrar o
#   contrato (ex.: reintroduzir o cap de execução em prd, que derruba o OTP de login depois do
#   50º envio), este teste fica vermelho. Cobre P0-3 (cap só fora de prd) e o parse de destinatário.
# Saída: exit 0 se vet+test passam; 1 se falham OU se faltar `go` (gate que não roda não pode dar verde).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC="${IAM_DOC:-$HERE/../references/iam.md}"
command -v go >/dev/null 2>&1 || { echo "FALHOU: 'go' ausente — o teste do guard não rodou (não rodar reprova)"; exit 1; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/mail"

# bloco N (0-based) dos blocos ```go dentro da seção "## 3.1" até "## 4."
block() {
  awk -v want="$1" '
    /^## 3\.1 /{on=1; next}
    /^## 4\. /{on=0}
    on && /^```go$/{inb=1; n++; next}
    on && /^```$/{inb=0; next}
    on && inb && n==want+1 {print}
  ' "$DOC"
}

{
  block 0 | sed '0,/^package mail$/s//package mail\n\nimport (\n\t"bytes"\n\t"context"\n\t"encoding\/json"\n\t"errors"\n\t"fmt"\n\t"io"\n\t"log\/slog"\n\tnetmail "net\/mail"\n\t"net\/http"\n\t"strings"\n\t"sync"\n\t"sync\/atomic"\n\t"time"\n)/'
  block 1
  block 2
} > "$W/mail/mail.go"

{
  printf 'package mail_test\n\nimport (\n\t"context"\n\t"errors"\n\t"fmt"\n\t"sync/atomic"\n\t"testing"\n\t"time"\n\n\t"guardcheck/mail"\n)\n\n'
  block 4
} > "$W/mail/guard_test.go"

printf 'module guardcheck\n\ngo 1.22\n' > "$W/go.mod"

for f in mail.go guard_test.go; do
  [ -s "$W/mail/$f" ] || { echo "FALHOU: bloco vazio ao extrair $f de $DOC (layout da §3.1 mudou?)"; exit 1; }
done

cd "$W"
export GOTOOLCHAIN=local
if ! out=$(go vet ./... 2>&1); then echo "FALHOU: go vet"; echo "$out"; exit 1; fi
if ! out=$(go test -race -count=1 ./... 2>&1); then echo "FALHOU: go test"; echo "$out"; exit 1; fi
echo "$out"
for t in TestGuard_PrdNaoTemCapPorProcesso TestGuard_CapAbortaExecucao TestGuard_RecusaListaEInjecao; do
  vout=$(go test -count=1 -run "^$t\$" -v ./... 2>&1 || true)
  grep -q -- "--- PASS: $t" <<<"$vout" || { echo "FALHOU: $t não rodou/não passou"; exit 1; }
done
echo "iam-guard.test: OK"
