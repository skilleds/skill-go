#!/usr/bin/env bash
# archive-secret-scan.test.sh — vermelho e verde plantados do scan de segredo/PII no archive.
# O quê: prova que o scan REPROVA segredo/PII em MD/JSONL de `*_archive/` e PASSA archive limpo.
# Segredos falsos são montados em tempo de execução (push protection do GitHub bloqueia literal).
# Saída: exit 0 se todos os casos passam, 1 se algum falhou.
# strict-ok: harness de teste — roda TODOS os casos e soma; com `-e` pararia no primeiro vermelho (`schematize-shell` -> `references/piso.md` secao 1)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
rc=0

# PATH sem gitleaks: o caminho de regex é o que este teste cobre (com gitleaks o gate delega a ele).
mkdir -p "$W/bin"
for t in bash find grep sed head dirname; do
  p="$(command -v "$t")" && ln -s "$p" "$W/bin/$t"
done
run() { PATH="$W/bin" "$W/bin/bash" "$HERE/archive-secret-scan.sh" "$@" 2>&1; }

expect() { # expect "descrição" rc_esperado rc_real saida [padrão]
  local d="$1" want="$2" got="$3" out="$4" pat="${5:-}"
  if [ "$got" -eq "$want" ] && { [ -z "$pat" ] || grep -q -- "$pat" <<<"$out"; }; then
    echo "  ok  $d"
  else
    echo "  FALHOU $d (rc=$got, esperado $want)"; echo "$out" | sed 's/^/      /'; rc=1
  fi
}

P="$W/proj/proj_archive"; mkdir -p "$P/context"
AWS="AKIA$(printf 'ABCDEFGHIJKLMNOP')"                       # 4 + 16
CPF="123.456.789-09"
JWT="eyJ$(printf 'a%.0s' {1..12}).$(printf 'b%.0s' {1..12}).$(printf 'c%.0s' {1..12})"

echo "── VERDE: sem MD no archive"
mkdir -p "$W/vazio"; out=$(run "$W/vazio"); expect "nada a varrer" 0 $? "$out" "nada a varrer"

echo "── VERDE: archive limpo"
printf '# Handoff\nDecidimos usar fila. Sem segredo aqui.\n' > "$P/context/handoff.md"
out=$(run "$W/proj"); expect "archive limpo passa" 0 $? "$out" "OK"

echo "── VERDE: segredo FORA de *_archive/ é ignorado"
printf 'chave %s\n' "$AWS" > "$W/proj/README.md"
out=$(run "$W/proj"); expect "fora do archive não conta" 0 $? "$out"
rm -f "$W/proj/README.md"

echo "── VERMELHO: chave AWS no handoff"
printf 'chave %s\n' "$AWS" > "$P/context/aws.md"
out=$(run "$W/proj"); expect "AWS key reprova" 1 $? "$out" "BLOQUEADO"
if grep -q "$AWS" <<<"$out"; then echo "  FALHOU saída vazou o segredo inteiro"; rc=1; else echo "  ok  achado redigido na saída"; fi
rm -f "$P/context/aws.md"

echo "── VERMELHO: JWT"
printf 'token %s\n' "$JWT" > "$P/context/jwt.md"
out=$(run "$W/proj"); expect "JWT reprova" 1 $? "$out" "candidato"
rm -f "$P/context/jwt.md"

echo "── VERMELHO: chave privada PEM"
printf -- '-----BEGIN %s PRIVATE KEY-----\n' "RSA" > "$P/context/pem.md"
out=$(run "$W/proj"); expect "PEM reprova" 1 $? "$out"
rm -f "$P/context/pem.md"

echo "── VERMELHO: CPF (PII) em .jsonl"
printf '{"nota":"cliente %s"}\n' "$CPF" > "$P/context/log.jsonl"
out=$(run "$W/proj"); expect "CPF em jsonl reprova" 1 $? "$out"
rm -f "$P/context/log.jsonl"

echo "── VERMELHO: password literal"
printf 'password = %s\n' "hunter2hunter2" > "$P/context/pw.md"
out=$(run "$W/proj"); expect "password= reprova" 1 $? "$out"
rm -f "$P/context/pw.md"

echo "── VERDE de novo: depois de limpar, volta a passar"
out=$(run "$W/proj"); expect "limpo de novo" 0 $? "$out"

[ "$rc" -eq 0 ] && echo "archive-secret-scan.test: OK" || echo "archive-secret-scan.test: FALHOU"
exit "$rc"
