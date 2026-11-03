# Testes — recorte Go

> **PONTEIRO, não cópia.** A **disciplina de teste** da casa é da **`schematize-qa`**: a pirâmide,
> teste de COMPORTAMENTO (não "renderizou"), o "verde de verdade" (smoke com asserção de conteúdo +
> assertion negativa + self-check que força uma falha conhecida), cobertura útil, a11y, regressão
> visual, contrato/dados, **flaky** (quarentena com prazo e dono), o fluxo **plan-first**
> (`/qa-plan` → `/qa-run`) e os **gates de CI que travam o merge**. Leia
> `schematize-qa` → `references/estrategia.md`, `references/categorias.md`,
> `references/execucao.md` e `references/flaky.md`.
>
> **Segurança ofensiva** (rejeição rota a rota, injeção/coerção, IDOR/BOLA, cross-tenant) é a
> **`schematize-pentest`** — não é Q.A. e não mora aqui.
>
> Aqui fica **só o que muda em Go**: o runner, a sintaxe, e as armadilhas do dialeto.
>
> *(Este arquivo e a antiga reference *testes-execucao* eram, juntos, ~450 linhas por skill — 66% já
> duplicado na `schematize-qa`, 23% que pertence à `schematize-pentest` e ~2% idiomático de
> verdade. Deriva por cópia foi o achado da Classe C/D da vistoria de 2026-08-21.)*

## O runner e o comando

```bash
go test -race -cover ./...          # -race SEMPRE: corrida é bug, não "re-roda"
go test -run TestX -v ./pkg/...     # um caso
gotestsum --format testname         # saída legível no CI
go test -coverprofile=c.out ./... && go tool cover -func=c.out
```

## `testing/synctest` — concorrência testada sem `sleep` (disponível desde o Go 1.25)

A skill exige timeout, cancelamento e `-race` em toda parte e não citava a **única ferramenta do
stdlib feita para testar isso deterministicamente**. `synctest.Test` roda a função numa "bolha" com
**relógio falso**: o tempo só avança quando **todas** as goroutines da bolha estão bloqueadas, e aí
ele salta direto para o próximo timer.

```go
func TestTimeoutExpira(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		go servidorLento(ctx)
		time.Sleep(5 * time.Second) // instantâneo: o relógio da bolha SALTA
		synctest.Wait()             // espera as goroutines da bolha quietarem
		if ctx.Err() == nil {
			t.Fatal("esperava o contexto expirado")
		}
	})
}
```

O ganho não é velocidade — é **determinismo**: o teste que dependia de `time.Sleep(50ms)` "para dar
tempo" passa a não ter janela de corrida nenhuma, e é exatamente esse teste que vira flaky no CI
carregado. Duas ressalvas: **I/O real (rede, disco) não entra na bolha** — o relógio não sabe
esperá-lo, então isole a borda —, e goroutine que **escapa** da bolha faz o teste falhar, o que é
bom: vazamento de goroutine vira erro em vez de mistério.

## O que muda de forma em Go

- **`-race` é piso, não opção.** O detector de concorrência fica ligado em todo `go test` do CI.
  Teste que só falha com `-race` é **bug de produção**, não flakiness — vai para correção, nunca
  para quarentena.
- **Table-driven é o default**, com `t.Run(nome, ...)` por caso: o nome do subteste é o que aparece
  no CI, então ele descreve o **comportamento**, não o número do caso.
- **`t.Parallel()` exige cuidado com a variável do laço** em Go < 1.22 (`tc := tc`); a partir do
  1.22 o `for` cria a variável por iteração. Sem isso, todos os subtestes rodam o **último** caso —
  o verde mentiroso mais silencioso do Go.
- **`t.Cleanup` em vez de `defer`** em helper de teste: roda também quando o subteste falha.
- **Golden files** (`-update` como flag do teste) para saída grande; o `.golden` entra no diff do PR
  — se ninguém lê o diff do golden, o teste virou carimbo.
- **`httptest.Server`** para o cliente HTTP e **`testcontainers-go`** para banco/broker: mock de
  driver esconde erro de SQL real.
- **Property-based:** `gopter` ou `rapid`. **Mutation:** `go-mutesting` no domínio crítico.
- **Fuzzing nativo** (`func FuzzX(f *testing.F)`) para parser e validador — o corpus vive em
  `testdata/fuzz/` e **entra no repo**.

## Onde divergir da base, a base manda

O piso é o mesmo: teste é **visto falhar no vermelho** antes de valer; cobertura é **contrato**
(não se baixa a régua para passar o CI); **teste nunca dispara efeito externo real** — endereço no
domínio de teste em rota nula, provider = sink, cap por execução, e a caixa se confere **lendo do
sink** (`references/iam.md` §3.1 desta skill; normativa em `schematize-engineering` →
`references/efeitos-externos.md`); e **gate não se desliga "por enquanto"**.
