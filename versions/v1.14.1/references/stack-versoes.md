# Anexo volátil — versões e limiares (Go)

> Parte da skill **schematize-go**. **Fonte volátil:** tudo aqui tem prazo de validade e é
> atualizado **à parte** do corpo normativo — que não deve cravar número nenhum (o lint do
> catálogo, regra `anexo-volatil`, reprova quando crava).
>
> **Verificado em: 2026-08-21.** Cadência: **revisão trimestral**, e sempre antes de um release da
> skill. Confirme na fonte (`go.dev/dl`, release notes, endoflife.date) antes de pinar.

## Go — a linha suportada

- **Piso normativo: rodar numa linha SUPORTADA.** O Go dá suporte às **duas releases majors mais
  recentes** — quando a `N` sai, a `N-2` **para de receber patch de segurança**. Ficar fora dessa
  janela é violação de cadeia de suprimentos (`references/cadeia-suprimentos.md`), não dívida.
- **Calibração verificada em 2026-08-21:** corrente é a **1.27**; a **1.26** ainda recebe patch; a
  **1.25 já saiu da janela**.
- `go.mod` declara a versão da linguagem; a **toolchain** vem pinada (`toolchain go1.x.y`) para o
  build ser reprodutível entre máquina e CI.
- Imagem base **por digest** (`golang:1.x-alpine@sha256:…`), nunca por tag móvel.

## Concorrência — recursos que dependem de versão (✔ verificado em 2026-10-14, go.dev/doc)

Corpo normativo: `references/concorrencia.md`.

- **`testing/synctest` com `synctest.Test`**: GA no **1.25**. No 1.24 existia só atrás de
  `GOEXPERIMENT=synctest` com API diferente (`synctest.Run`), removida no 1.26. Projeto em 1.24 não
  usa o exemplo do reference sem subir a versão.
- **`sync.WaitGroup.Go`**: a partir do **1.25**.
- **Variável de laço por iteração**: a partir do **1.22**, e só vale se o `go.mod` declara `go >= 1.22`.
- **Perfil `goroutineleak`** (`runtime/pprof`): **experimental** no 1.26, atrás de
  `GOEXPERIMENT=goroutineleakprofile`; reverificar antes de depender dele.
- **`goleak`** (`go.uber.org/goleak`): corrente **v1.3.0** em 2026-10-14.

## Ferramental

| Ferramenta | Papel | Nota |
|---|---|---|
| `golangci-lint` | agregador de lint no CI | **config no schema v2** — o v1 é rejeitado; ver abaixo |
| `govulncheck` | vulnerabilidade com **alcançabilidade** (só reporta o que seu código chama) | roda no CI, trava o merge |
| `gotestsum` | saída de teste legível/JUnit no CI | |
| `gopter` / `rapid` | property-based | domínio crítico |
| `go-mutesting` | mutation testing | domínio crítico |
| `testcontainers-go` | banco/broker reais em teste de integração | |

> **`.golangci.yml` — schema v2.** ✔ 2026-08-21: o schema **v1 foi descontinuado** e um arquivo v1
> **não vira lint com aviso: vira erro de CONFIG**. Num CI que não trata o exit code, isso é um
> gate que deixou de rodar sem ninguém ver — o verde mentiroso clássico. O arquivo precisa começar
> com `version: "2"`, e o passo de CI precisa **falhar** se o `golangci-lint` sair diferente de 0.

## Infra e protocolo (fora do escopo desta skill)

Kubernetes, PostgreSQL, Redis, OpenTelemetry e afins: **`schematize-infra`**. Frontend:
**`schematize-web`** → `references/stack-versoes.md`. Não duplique os números aqui.

## Regra que NÃO é volátil

**Mudança de versão major exige ADR.** Isso vale independente do número, e por isso mora no corpo
normativo (`references/entrega.md`), não neste anexo.
