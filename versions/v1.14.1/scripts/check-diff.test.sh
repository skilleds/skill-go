#!/usr/bin/env bash
# check-diff.test.sh — vermelho e verde plantados do gate check-diff.sh.
# O quê: monta um repo git temporário (base `main` + commit de feature) e prova que o gate
#   REPROVA cada violação de piso do diff e PASSA diff limpo. Nada toca o repo real.
# Saída: exit 0 se todos os casos passam, 1 se algum falhou.
# strict-ok: harness de teste — roda TODOS os casos e soma; com `-e` pararia no primeiro vermelho (`schematize-shell` -> `references/piso.md` secao 1)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
rc=0

new_repo() { # cria $W/r com um commit base em `main`, entra nele, abre a branch `feat`
  rm -rf "$W/r"; mkdir -p "$W/r"; cd "$W/r" || exit 2
  git init -q -b main . && git config user.email t@t && git config user.name t
  git config commit.gpgsign false
  echo base > base.txt; git add -A; git commit -qm base
  git checkout -qb feat
}
commit_feat() { git add -A; git commit -qm feat; }
gate() { bash "$HERE/check-diff.sh" "${1:-main}" 2>&1; }
expect() { # expect "descrição" rc_esperado rc_real saída [padrão]
  local d="$1" want="$2" got="$3" out="$4" pat="${5:-}"
  if [ "$got" -eq "$want" ] && { [ -z "$pat" ] || grep -q -- "$pat" <<<"$out"; }; then
    echo "  ok  $d"
  else
    echo "  FALHOU $d (rc=$got, esperado $want, padrão '$pat')"; echo "$out" | sed 's/^/      /'; rc=1
  fi
}
plant() { # plant "descrição" arquivo "conteúdo" rc padrão
  new_repo; mkdir -p "$(dirname "$2")"; printf '%s\n' "$3" > "$2"; commit_feat
  local out; out=$(gate); expect "$1" "$4" $? "$out" "${5:-}"
}

echo "── VERDE"
plant "diff limpo em Go passa" svc/ok.go 'package svc
func Soma(a, b int) int { return a + b }' 0 "check-diff: OK"
plant "diff só de docs passa" docs/x.md '# nada' 0
plant "violação em arquivo de TESTE é isenta" svc/a_test.go 'var _ = tls.Config{InsecureSkipVerify: true}' 0
plant "violação em migrations/ é isenta" db/migrations/001.go 'var _ = tls.Config{InsecureSkipVerify: true}' 0

echo "── VERMELHO (cada regra do piso)"
plant "TLS desabilitado" svc/t.go 'var _ = tls.Config{InsecureSkipVerify: true}' 1 "TLS"
plant "NEXT_PUBLIC com segredo" web/e.ts 'const k = process.env.NEXT_PUBLIC_API_SECRET' 1 "NEXT_PUBLIC"
plant "CORS *" svc/c.go 'w.Header().Set("Access-Control-Allow-Origin", "*")' 1 "CORS"
plant "nosec inline" svc/n.go 'x := 1 // nolint:gosec' 1 "regra de segurança"
plant "erro engolido" web/s.ts 'try { f() } catch {}' 1 "erro engolido"
plant "tipo silenciado (any)" web/a.ts 'let x: any = 1' 1 "tipo silenciado"
plant "teste pulado" web/p.ts 'it.skip("x", () => {})' 1 "teste pulado"
plant "SQL por concatenação" svc/q.go 'db.Query("SELECT * FROM u WHERE id=" + req.ID)' 1 "SQL"
plant "PHP no diff" legado/x.php '<?php echo 1;' 1 "PHP"

echo "── VERMELHO: tamanho de arquivo"
new_repo; mkdir -p svc
{ echo 'package svc'; for i in $(seq 1 800); do echo "var v$i = $i"; done; } > svc/big.go; commit_feat
out=$(gate); expect "arquivo >750 linhas bloqueia" 1 $? "$out" "750"
new_repo; mkdir -p svc
{ echo 'package svc'; for i in $(seq 1 350); do echo "var v$i = $i"; done; } > svc/mid.go; commit_feat
out=$(gate); expect "arquivo médio (>300 úteis) só avisa" 0 $? "$out" "ATENÇÃO"

echo "── VERMELHO: base inexistente não pode virar verde"
new_repo; printf 'var _ = tls.Config{InsecureSkipVerify: true}\n' > t.go; commit_feat
out=$(gate refs/nao/existe); expect "base inválida reprova" 1 $? "$out" "base"

echo "── 2 violações são TODAS reportadas (coletor, não aborta no primeiro)"
new_repo; printf 'let a: any = 1\nlet b: any = 2\n' > m.ts; commit_feat
out=$(gate); n=$(grep -c 'tipo silenciado' <<<"$out")
if [ "$n" -eq 2 ]; then echo "  ok  2 achados"; else echo "  FALHOU achados=$n"; rc=1; fi

[ "$rc" -eq 0 ] && echo "check-diff.test: OK" || echo "check-diff.test: FALHOU"
exit "$rc"
