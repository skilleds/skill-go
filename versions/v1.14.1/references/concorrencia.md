# Concorrência (Go)

> Parte da skill **schematize-go**. Os erros mais caros de um backend Go não são de compilação: são
> de runtime concorrente — goroutine que vaza, `context` ignorado, data race que só aparece em
> produção, canal sem dono e fan-out sem limite. Esta reference é o piso de concorrência. Liga com
> `testes.md` (race detector no CI), `dados-eventos.md` (resiliência, jobs) e `operacao.md`
> (graceful shutdown). Versões do Go e do ferramental ficam em `stack-versoes.md`.

## Índice
- C1. `context`: toda operação bloqueante é cancelável
- C2. Ciclo de vida de goroutine e `errgroup`
- C3. Goroutine leak e `goleak`
- C4. Data race e o race detector
- C5. `sync` ou canais
- C6. Backpressure, fan-out e shutdown
- C7. Testar concorrência: `testing/synctest`

---

## C1. `context`: toda operação bloqueante é cancelável

**MUST**
- **`ctx context.Context` é o primeiro parâmetro** de toda função que faz I/O, espera ou chama
  outra que o faz. O `ctx` vem da borda (request, job, `signal.NotifyContext` no `main`) e **desce**;
  nunca `context.Background()` no meio da cadeia (só em `main`, init e testes).
- **Toda chamada externa tem prazo:** `context.WithTimeout`/`WithDeadline` na fronteira, mais
  `http.Client{Timeout: ...}` / `db.QueryContext`. Nada espera para sempre.
- **`defer cancel()` logo após criar** o contexto derivado (`go vet` reprova o `cancel` perdido).
- **Quem bloqueia escuta `ctx.Done()`** (`select` com `case <-ctx.Done(): return ctx.Err()`); o erro
  devolvido é `ctx.Err()` (ou o embrulha com `%w`), nunca engolido. Distinga `context.Canceled`
  (cliente foi embora, não é falha do serviço) de `context.DeadlineExceeded` (dependência lenta).

**VETADO**
- Guardar `ctx` em struct de longa vida; passar `nil` como `ctx`.
- `context.Value` para parâmetro de negócio (só dados de escopo de requisição: `trace_id`, identidade
  já verificada). `tenant_id` vem do token verificado (`seguranca.md`), nunca de `ctx.Value` preenchido
  por input do cliente.

---

## C2. Ciclo de vida de goroutine e `errgroup`

**MUST**
- **Toda goroutine tem dono, fim e canal de erro.** Quem a lança sabe quando ela termina e recebe o
  erro. `go func() { ... }()` solto, sem `WaitGroup`/`errgroup`, é VETADO em caminho de produção.
- **Fan-out com erro e cancelamento = `golang.org/x/sync/errgroup`:** `g, ctx := errgroup.WithContext(ctx)`;
  o primeiro erro cancela o `ctx` dos irmãos; `g.Wait()` devolve o primeiro erro. Use **`g.SetLimit(n)`**
  para limitar a concorrência (fan-out de 10k itens sem limite derruba o upstream).
- **Capture a variável certa.** A variável de `for` é por iteração nas versões recentes, mas só se o `go.mod`
  declarar a versão da linguagem que trouxe isso (ver `stack-versoes.md`); em dúvida, copie (`it := it`).
- **`recover()` na fronteira da goroutine** que roda código de terceiros ou de plugin: pânico em goroutine
  derruba o processo inteiro. Converta em `error`, logue com `trace_id`, não mascare.

```go
// ProcessAll processa os itens com no máximo 8 em voo; o primeiro erro cancela os demais.
func ProcessAll(ctx context.Context, items []Item) error {
	g, ctx := errgroup.WithContext(ctx)
	g.SetLimit(8)
	for _, it := range items {
		g.Go(func() error { return process(ctx, it) })
	}
	return g.Wait()
}
```

---

## C3. Goroutine leak e `goleak`

Goroutine vazada (bloqueada para sempre num canal, `Mutex`, `WaitGroup` ou I/O sem prazo) é memória e
file descriptor perdidos, e **só aparece em produção** depois de dias. As três causas reais: envio ou
recebimento num canal que ninguém mais lê, ausência de `ctx.Done()` no `select`, e `time.Ticker`/`Timer`
sem `Stop`.

**MUST**
- **Todo pacote com goroutine tem teste com `goleak`** (`go.uber.org/goleak`): `TestMain` com
  `goleak.VerifyTestMain(m)` ou, por teste, `defer goleak.VerifyNone(t)`. O leak vira vermelho no CI,
  não ticket de produção.
- **Canal enviado de goroutine é `buffered(1)` ou tem `select` com `ctx.Done()`** no envio — o caso clássico
  é o resultado que ninguém lê porque o chamador desistiu por timeout.
- **`ticker.Stop()` / `timer.Stop()` em `defer`.**

**SHOULD**
- Em produção, exponha `/debug/pprof/goroutine` (rede interna, nunca pública) e alerte em crescimento
  monotônico de `go_goroutines`. Detalhe em `observabilidade.md`.
- O perfil `goroutineleak` do runtime é **experimental** (atrás de `GOEXPERIMENT`): útil para diagnóstico,
  **não** substitui o `goleak` no teste. Status e versão em `stack-versoes.md`.

```go
func TestMain(m *testing.M) { goleak.VerifyTestMain(m) }
```

---

## C4. Data race e o race detector

**MUST**
- **`go test -race ./...` no CI, sem exceção** (e no `/go-qa`). `-race` não é opcional nem "só no nightly":
  race que passa em teste e explode em produção é o bug mais caro da linguagem. Nunca retire `-race` para
  "acelerar" o CI — acelere com `-short`/paralelismo, não perdendo o detector.
- **Todo dado compartilhado e mutável tem um dono:** protegido por `sync.Mutex`/`RWMutex`, por `sync/atomic`,
  ou confinado a **uma** goroutine que recebe pedidos por canal. "Só lê" também conta se alguém escreve.
- **Mapa não é concorrente.** `map` com escrita concorrente é panic (`fatal error: concurrent map writes`),
  não race silenciosa. Use `sync.Mutex` + map, ou `sync.Map` só no padrão chave-estável/escrita-rara.
- **Teste concorrente com `t.Parallel()` e `-count=N`** (`-shuffle=on`) para dar chance ao detector de pegar a
  corrida; um único run verde prova pouco.

**VETADO**
- Copiar `sync.Mutex`/`WaitGroup` por valor (`go vet` copylocks reprova).
- "Dupla checagem" de flag sem `atomic` (`if !ready { lock; ... }` lendo `ready` fora do lock).

---

## C5. `sync` ou canais

Regra de bolso (a da própria linguagem): **canal para transferir ownership e orquestrar; mutex para
proteger estado.** Nenhum dos dois é "o jeito Go".

| Situação | Use |
|---|---|
| Proteger contador/cache/mapa acessado por várias goroutines | `sync.Mutex`/`RWMutex` (ou `atomic` para um escalar) |
| Passar o trabalho (e a posse do dado) de produtor para consumidor | canal |
| Sinalizar "terminou"/"cancele" para N interessados | `close(chan struct{})` ou `ctx` |
| Fan-out/fan-in com erro e limite | `errgroup` + `SetLimit` |
| Inicialização única preguiçosa | `sync.Once`/`sync.OnceValue` |
| Espera de N tarefas sem erro | `sync.WaitGroup` (na linguagem recente, `wg.Go(func(){...})` — ver `stack-versoes.md`) |

**MUST**
- **Quem cria o canal é quem o fecha** (o emissor). Receptor nunca fecha; fechar duas vezes é panic.
- Seção crítica **curta e sem I/O**: não segure `Mutex` através de chamada de rede, de banco ou de canal.
- Ordem de aquisição de locks **consistente** (A depois de B em todo lugar) — evita deadlock.

**SHOULD**
- Se a contenção de lock aparece no profile, passe a **uma goroutine dona do estado** e mensagens por canal.

---

## C6. Backpressure, fan-out e shutdown

**MUST**
- **Canais e filas têm capacidade definida.** Canal sem buffer é ponto de sincronização; com buffer, o `N`
  é decisão (e vira métrica de profundidade). Fila ilimitada (slice crescendo atrás de um canal) é OOM
  esperando carga. **Política de cheio explícita:** bloquear (backpressure), descartar com contador, ou
  rejeitar com erro — decidida, não acidental.
- **Concorrência limitada em fan-out** (`errgroup.SetLimit`, semáforo `chan struct{}` ou
  `golang.org/x/sync/semaphore`), nunca uma goroutine por item de entrada não confiável.
- **Graceful shutdown:** `ctx, stop := signal.NotifyContext(ctx, os.Interrupt, syscall.SIGTERM)`; ao cancelar,
  parar de aceitar trabalho (`srv.Shutdown(shutdownCtx)` com prazo), **drenar** o que está em voo
  (`g.Wait()`), fechar conexões/flush de buffer em ordem inversa à abertura e só então sair. Falha ao
  drenar no prazo é logada com `trace_id`, não ignorada. Liga com `operacao.md`.

---

## C7. Testar concorrência: `testing/synctest`

`testing/synctest` (API `synctest.Test`; a versão em que ficou estável e o que mudou do experimento está em
`stack-versoes.md`) roda o teste numa **bolha** com relógio virtual: `time.Sleep`, `Timer`, `Ticker` e
`context.WithTimeout` avançam instantaneamente quando todas as goroutines da bolha estão bloqueadas, e
`synctest.Wait()` espera todas bloquearem. Resultado: teste de timeout/retry/backoff **determinístico e
em microssegundos**, sem `time.Sleep(…)` real e sem flakiness.

**MUST**
- Teste de timeout, retry com backoff, debounce e expiração de cache usa `synctest.Test`, não `Sleep`
  real nem relógio injetado ad hoc.
- Combine com `goleak`/`-race`: a bolha não dispensa nenhum dos dois.

**VETADO**
- `time.Sleep(…)` em teste para "dar tempo" à goroutine (flaky por construção).

```go
func TestRetryBackoff(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		calls := 0
		ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
		defer cancel()
		err := Retry(ctx, func() error { calls++; return errTransient }) // backoff real: 1s,2s,4s...
		synctest.Wait()
		if !errors.Is(err, context.DeadlineExceeded) || calls < 3 {
			t.Fatalf("err=%v calls=%d", err, calls)
		}
	})
}
```

> Regra de bolso: **todo `ctx` desce, toda goroutine tem dono e fim, todo canal tem capacidade, e `-race` +
> `goleak` rodam no CI.** O compilador garante tipos; concorrência correta é com você.
