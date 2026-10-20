# padroes codigo — recorte Go

> **PONTEIRO, não cópia.** A normativa deste tema é da base: **`schematize-engineering`** →
> `references/padroes-codigo.md`. Leia lá primeiro; aqui fica **só o que muda em Go**.
>
> **Onde este arquivo divergir da base, a BASE MANDA** (`SKILL.md` §"Precedência e herança").
> Este arquivo era um clone com **100%** de conteúdo
> idêntico à base — deriva por cópia foi o achado da Classe C da vistoria de 2026-08-21, e ela
> já tinha atingido piso de segurança (o `argon2id-only` da casa virou "ou PBKDF2" numa skill,
> o rol de 6 linguagens virou "só Go e Rust" em três). Manter uma cópia é manter a próxima deriva.
O piso da base vale integralmente. O que **muda em Go** é o idioma corrente — e é aqui que a skill
tinha um buraco: ela descrevia um Go anterior a três mudanças que já são o jeito normal de escrever.

## Iteradores: `iter.Seq` e range-over-func (disponível desde o Go 1.23)

Uma função pode ser percorrida por `for … range`. Isso substitui os três padrões antigos de
"entregar uma sequência": devolver slice inteiro (aloca tudo), expor um `Next()`/cursor à mão
(estado espalhado) ou receber um callback `func(T) bool` (que inverte o controle e complica o
`break`).

```go
// iter.Seq[T] é `func(yield func(T) bool)`. O `yield` devolvendo false = o chamador deu break.
func Ativos(db *sql.DB) iter.Seq2[Usuario, error] {
	return func(yield func(Usuario, error) bool) {
		rows, err := db.Query("SELECT id, email FROM usuarios WHERE ativo")
		if err != nil {
			yield(Usuario{}, err)
			return
		}
		defer rows.Close() //nolint:errcheck
		for rows.Next() {
			var u Usuario
			if err := rows.Scan(&u.ID, &u.Email); err != nil {
				yield(Usuario{}, err)   // erro vai POR DENTRO da sequência…
				return
			}
			if !yield(u, nil) {
				return                   // …e o break do chamador chega aqui
			}
		}
		if err := rows.Err(); err != nil {
			yield(Usuario{}, err)
		}
	}
}

for u, err := range Ativos(db) {   // consumo idiomático
	if err != nil { return err }
	// …
}
```

**Use `iter.Seq2[T, error]` quando a produção pode falhar** — é o que evita o antipadrão de
guardar o erro num campo do iterador e torcer para alguém checar depois. E lembre: *o `defer` do
produtor só roda quando a sequência termina ou o chamador dá `break`* — não deixe recurso caro
preso a um consumidor lento. `slices` e `maps` já expõem `All`/`Values`/`Keys` nesse formato.

## `go tool` — o fim do hack do `tools.go` (disponível desde o Go 1.24)

Ferramenta de build (mock, lint, gerador) entra no `go.mod` com `go get -tool` e roda com
`go tool <nome>`; a versão fica **versionada junto com o módulo**. Isso aposenta o
`//go:build tools` + `import _` num arquivo `tools.go`, que era um hack para o `go mod tidy` não
apagar a dependência — e que fazia toda máquina instalar a ferramenta "na mão", cada uma numa
versão. **CI e dev passam a rodar a mesma versão da ferramenta, sem `go install` global.**

## `testing/synctest` — o teste determinístico de concorrência (disponível desde o Go 1.25)

Ver `references/testes.md`. É citado aqui porque muda o **jeito de escrever** código com tempo:
se o teste pode controlar o relógio, some a tentação de espalhar `time.Sleep(50 * time.Millisecond)`
"para dar tempo" — que é a origem do flaky que a `schematize-qa` manda colocar em quarentena.
