# Arquitetura, Camadas, Repositórios e Linguagens


> **PONTEIRO, não cópia.** A normativa deste tema é da base: **`schematize-engineering`** →
> `references/arquitetura.md`. Leia lá primeiro; aqui fica **só o que muda em Go**.
>
> **Onde este arquivo divergir da base, a BASE MANDA** (`SKILL.md` §"Precedência e herança").
> Em 2026-08-21 os blocos idênticos à base foram **podados mecanicamente** (`tools/podar-clone.mjs`),
> que é por que a numeração dos itens **salta**: o número é o da base, e o item que não aparece aqui
> é porque **não muda nesta linguagem** — procure-o lá. Manter a cópia era manter a próxima deriva
> (foi assim que o `argon2id-only` da casa virou "ou PBKDF2" numa skill e o rol de 6 linguagens
> virou "só Go e Rust" em três).

## 2. Estrutura de Repositórios

- **Independência de runtime (cada serviço é entidade à parte):** todo serviço **sobe e opera sozinho**. A indisponibilidade de qualquer outro serviço **nunca** impede o boot nem derruba este — depender de outro serviço para *iniciar/funcionar* é VETADO (nada de "o `ledger` não sobe se o `core` estiver fora"). Dependente ausente vira **degradação graciosa** (fallback, resposta parcial, enfileira e segue), nunca crash em cascata. Como não perder o dado quando a chamada falha: `schematize-engineering` -> `references/dados-eventos.md` (§18).

- **`<projeto>_ops` (control plane de desenvolvimento):** todo sistema multi-repo tem um repo **`<projeto>_ops`** — a ferramenta de operação do workspace, rodada por dev/agente e **fora do runtime do produto**. Faz bootstrap/instalação, update, manutenção, troubleshooting e roda os testes unitários/debug **através de todos os repos** (clona, sobe/para, migra, semeia e testa cada serviço). Não é microserviço nem é deployado com o produto; é essencial pra tocar um sistema de múltiplos repositórios. Como toda ferramenta, sobe com **observabilidade integrada** (Grafana/LGTM+, ver `schematize-engineering` -> `references/observabilidade.md` §16).

## 3. Linguagens

**Backend — uma linguagem do ROL SANCIONADO, escolhida por fit + ADR.**

O rol é **Go, Rust, Elixir, C#, Zig e Ruby** — cada uma com skill irmã. A escolha é por
**adequação ao serviço**, registrada em ADR (`schematize-engineering` → `references/linguagens.md`),
nunca por preferência do time. **Node como serviço backend e PHP estão em saída** (não recebem
serviço novo). *(Este arquivo dizia "apenas Go e Rust" — texto anterior à abertura do rol, que
transformava a skill num veto sobre as irmãs.)*

| Linguagem | Skill | Sufixo | Fit — quando escolher |
|---|---|---|---|
| **Go** | `schematize-go` | `_go` | Serviços de rede/API concorrentes, CLIs, tooling. |
| **Rust** | `schematize-rust` | `_rs` | Correção e segurança de memória críticas: auth, cripto, parsing hostil. |
| **Elixir** | `schematize-elixir` | `_ex` | Realtime, alta concorrência tolerante a falha (BEAM/OTP), pub-sub. |
| **C#** (.NET) | `schematize-csharp` | `_cs` | Ecossistema .NET/enterprise, integração Microsoft. |
| **Zig** | `schematize-zig` | `_zig` | Baixo nível, controle explícito de memória, interop com C, artefatos pequenos. |
| **Ruby** | `schematize-ruby` | `_rb` | DX de produto (Rails), scripts/automação, legado Ruby. |

> Sem tabela de "cenário → stack" aqui: não há linguagem padrão. O desempate pragmático, quando o fit empata, vive só na base (`schematize-engineering` → `references/linguagens.md`).

**Frontend — Node é 100% permitido (e só frontend).** Frontend baseado em Node é a stack da casa porque hoje é o melhor do mercado: **Next.js** é a stack principal, mas **Astro e outros frameworks consolidados** são permitidos. O server-side do próprio front (route handlers, server actions, BFF) faz parte do frontend e é governado pelo §13.4 e §38 (segredo só server-side, etc.). Isso vale **apenas** para frontend — **não** reabre Node como linguagem de serviço backend (ver o MUST abaixo e §3.1: backend novo em Node é proibido; o ganho marginal de tooling/npm não compensa o histórico de incidentes de segurança).

- Versão exata em uso fica no Anexo A.

- **Backend novo só em linguagem do rol sancionado, com ADR de fit.** Nenhum serviço backend novo em Node.

- **Não há default por gosto.** A escolha sai do guia de fit (`schematize-engineering` → `references/linguagens.md`) e vira ADR. Em empate técnico real, vence a linguagem que o time já opera em produção — e isso também vai no ADR, como o critério que foi.

### 3.1 Node legado (backend) — saída para o rol

Node como linguagem de **serviço backend** está em saída. Tudo que existe em Node backend migra para uma linguagem do **rol sancionado, por fit + ADR** (`schematize-engineering` → `references/linguagens.md`), guiado por esforço (não big-bang) e medido **por funcionalidade do módulo**, não por linha.

- **Gatilho de extração (~30%):** quando uma mudança atingir ~30% das funcionalidades do módulo (alteradas + novas), **não cresça o Node** — extraia essa(s) funcionalidade(s) para um **módulo à parte numa linguagem do rol (fit + ADR)** e incorpore o comportamento Node nessa nova base.

### 3.2 PHP — legado, migra por funcionalidade

- PHP não recebe serviço novo. Projeto existente em PHP é legado: **migra por funcionalidade quando tocado**, para uma linguagem do rol (fit + ADR), com plano (`schematize-engineering` → `references/linguagens.md` §2). Sem prazo forçado e sem "migração sumária".

## 4. Arquitetura

### 4.X DDD híbrido durante transição

- Manter teste de cobertura por camada (ver a `schematize-qa`) durante a transição — domain começa com 0%, sobe a cada PR.

## 6. Complexidade e Tamanho

> **Canônico em `references/padroes-codigo.md`** (arquivo ≤ 750 linhas — ~500 de código útil + ~250 de comentário; flag em > 300 úteis; uma função/unidade por arquivo; doc-comment obrigatório com motivo/comportamento/entradas/saídas/efeitos; e `MAPA.md`). Esta seção é o recorte de arquitetura desses pisos — não duplica a regra, contextualiza.

**MUST — arquivos pequenos, micro-funções**

- **Teto duro: ≤ 750 linhas/arquivo** (~250 de comentário + até ~500 de código útil). Acima disso, o arquivo **deve ser quebrado** — extraia responsabilidades em módulos menores e a lógica em **micro-funções** com nome que explica a intenção. Não existe "arquivo de 1200 linhas porque é coeso": coesão real cabe em arquivos pequenos colaborando.

- **Flag em > 300 linhas de código útil** (não bloqueia, mas **sempre sinaliza**): passou de 300 úteis (ou ~400 em observabilidade), é **indício** de função muito extensa / falta de abstração — registre como dívida e **revise quando as prioridades forem resolvidas**.

- **Funções pequenas e de responsabilidade única.** Ideal ≤ 50 linhas; função grande vira micro-funções compostas. Use case: uma responsabilidade.

- Exceções (não disparam quebra): testes, migrations, código gerado, schemas/fixtures.

**MUST — toda função documentada**

- **TODA função/método tem comentário** no formato de doc da linguagem (JSDoc, GoDoc, rustdoc). O comentário declara, no mínimo:
  - **O quê** — o que a função faz, em uma linha.
  - **Onde é usada / prevista** — quem chama, em que fluxo/camada ela foi pensada pra servir (ex.: "usado pelo use-case `CreateOrder`", "handler HTTP de `/v1/checkout`"). Isto dá contexto explícito de propósito e evita função órfã.
  - Parâmetros, retorno e efeitos colaterais relevantes.

- Esse comentário é a **fonte do índice de microfunções** (§39) — escreva pensando que ele será extraído e indexado, não como enfeite.

Convenção mínima (adapte à linguagem):

```
/**
 * O quê: valida o payload de checkout e cria o pedido.
 * Onde:  use-case CreateOrder; chamado pelo handler POST /v1/checkout.
 * Efeitos: persiste em orders, publica catalog.order.created via outbox.
 */
```

**Bloqueio rígido em CI**

- Arquivo de produção > 750 linhas (ou > ~500 de código útil) sem quebra (exceto as exceções acima) → bloqueia; > 300 úteis (~400 obs) → flag registrado.

- Função de produção sem doc-comment → bloqueia.

- Complexidade ciclomática > 15 em função de produção.

- Aninhamento > 4 níveis.

> Linha de código é proxy ruim para complexidade — complexidade ciclomática é a métrica honesta. Mas arquivo gigante e função sem contexto são dívidas óbvias: quebre e documente antes do merge.
