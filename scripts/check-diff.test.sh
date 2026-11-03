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

echo "── VERMELHO: vetos de LINGUAGEM (Rust)"
plant "Rust: unwrap() em produção" svc/a.rs 'fn f(x: Option<i32>) -> i32 { x.unwrap() }' 1 "unwrap"
plant "Rust: expect() em produção" svc/a.rs 'fn f(x: Option<i32>) -> i32 { x.expect("boom") }' 1 "unwrap"
plant "Rust: let _ = descarta Result" svc/a.rs 'fn f() { let _ = g(); }' 1 "let _"
plant "Rust: #[ignore] em teste (arquivo tests/)" svc/tests/it.rs '#[ignore]
#[test] fn t() {}' 1 "ignore"
plant "Rust: #[ignore] em teste inline" svc/b.rs '#[cfg(test)]
mod tests {
    #[ignore]
    #[test] fn t() {}
}' 1 "ignore"
plant "Rust: SQL com format!" svc/q.rs 'fn q(id: i32) -> String { format!("SELECT * FROM u WHERE id = {id}") }' 1 "format!"
echo "── VERDE: Rust legítimo"
plant "Rust: unwrap só em #[cfg(test)] no fim do arquivo é isento" svc/ok.rs 'pub fn soma(a: i32, b: i32) -> i32 { a + b }
#[cfg(test)]
mod tests {
    #[test]
    fn t() { let v: Option<i32> = Some(1); assert_eq!(v.unwrap(), 1); }
}' 0 "check-diff: OK"
plant "Rust: expect com check-diff:allow e motivo passa" svc/ok2.rs 'static R: &str = "x"; fn f() { let _r = regex().expect("padrão fixo validado no boot"); } // check-diff:allow: regex constante' 0
plant "Rust: allow SEM motivo não vale" svc/no.rs 'fn f(x: Option<i32>) -> i32 { x.unwrap() } // check-diff:allow:' 1 "unwrap"
plant "Rust: let _guard = (guard RAII) não é descarte" svc/g.rs 'fn f() { let _guard = lock(); }' 0

echo "── VERMELHO: vetos de LINGUAGEM (Go)"
plant "Go: t.Skip em _test.go (antes era código morto)" svc/a_test.go 'func TestX(t *testing.T) { t.Skip("depois") }' 1 "t.Skip"
plant "Go: _ = err" svc/e.go 'func f() { err := g(); _ = err }' 1 "_ = err"
plant "Go: //nolint sem justificativa" svc/n2.go 'defer rows.Close() //nolint:errcheck' 1 "nolint"
plant "Go: panic fora de main" svc/p.go 'func f() { panic("x") }' 1 "panic"
plant "Go: math/rand em arquivo de token" svc/r.go 'import "math/rand"
func newToken() int { return rand.Int() }' 1 "math/rand"
echo "── VERDE: Go legítimo"
plant "Go: //nolint com justificativa passa" svc/n3.go 'defer rows.Close() //nolint:errcheck // leitura já consumida; erro de Close irrelevante' 0
plant "Go: panic com check-diff:allow e motivo passa" svc/p2.go 'func mustInit() { panic("config ausente") } // check-diff:allow: falha de boot' 0
plant "Go: math/rand em arquivo SEM segredo (jitter) passa" svc/j.go 'import "math/rand"
func jitter() int { return rand.Intn(100) }' 0

echo "── MODO PRE-COMMIT (--staged) e o falso verde de base==HEAD"
staged() { # staged "descrição" arquivo "conteúdo" rc padrão  — NÃO comita: o hook roda antes do commit
  new_repo; mkdir -p "$(dirname "$2")"; printf '%s\n' "$3" > "$2"; git add -A
  local out; out=$(bash "$HERE/check-diff.sh" --staged 2>&1); expect "$1" "$4" $? "$out" "${5:-}"
}
staged "staged: violação no INDEX reprova (o hook enxerga)" svc/t.go 'var _ = tls.Config{InsecureSkipVerify: true}' 1 "TLS"
staged "staged: unwrap() no INDEX reprova" svc/a.rs 'fn f(x: Option<i32>) -> i32 { x.unwrap() }' 1 "unwrap"
staged "staged: diff limpo passa" svc/ok.go 'package svc
func Soma(a, b int) int { return a + b }' 0 "check-diff: OK"
new_repo; printf 'var _ = tls.Config{InsecureSkipVerify: true}\n' > t.go; git add -A
out=$(bash "$HERE/check-diff.sh" HEAD 2>&1); expect "base==HEAD (hook antigo 'check-diff.sh HEAD') reprova em vez de dar falso verde" 1 $? "$out" "próprio HEAD"
new_repo; out=$(bash "$HERE/check-diff.sh" HEAD --allow-empty 2>&1); expect "base==HEAD com --allow-empty é aceito conscientemente" 0 $? "$out"
new_repo; printf 'x\n' > a.txt; git add -A; out=$(bash "$HERE/check-diff.sh" --staged 2>&1); expect "staged só de docs passa" 0 $? "$out"

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
