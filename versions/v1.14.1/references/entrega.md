# Entrega: Templates, Flags, IA Assistida, DoD, Evolução e Índice


> **PONTEIRO, não cópia.** A normativa deste tema é da base: **`schematize-engineering`** →
> `references/entrega.md`. Leia lá primeiro; aqui fica **só o que muda em Go**.
>
> **Onde este arquivo divergir da base, a BASE MANDA** (`SKILL.md` §"Precedência e herança").
> Em 2026-08-21 os blocos idênticos à base foram **podados mecanicamente** (`tools/podar-clone.mjs`),
> que é por que a numeração dos itens **salta**: o número é o da base, e o item que não aparece aqui
> é porque **não muda nesta linguagem** — procure-o lá. Manter a cópia era manter a próxima deriva
> (foi assim que o `argon2id-only` da casa virou "ou PBKDF2" numa skill e o rol de 6 linguagens
> virou "só Go e Rust" em três).

## 35. Definition of Done

- [ ] **Teste emulado por IA (`simulated`, a `schematize-qa` (`references/categorias.md` §§5 e 10)) executado — 100% das rotas do inventário acessíveis pra quem deve e bloqueadas pra quem não deve; rota fantasma/morta = bloqueio**

- [ ] **Pentest de entrada limpo: sem `500`, sem coerção de tipo, sem eco não-escapado, sem vazamento cross-tenant (a `schematize-qa` (`references/categorias.md` §§5 e 10), a `schematize-pentest`)**

- [ ] Smoke tests executados em staging **(com asserção de conteúdo e self-check anti verde-mentiroso — a `schematize-qa` (`references/categorias.md` §§5 e 10))**

- [ ] **Nenhum efeito externo real fora de `prd` (se o projeto envia e-mail/SMS/push/webhook/cobrança):** provider default = **sink**, **guard deny-by-default dentro do provider** (com teste que **vê a recusa**), **cap por execução** válido em TODOS os ambientes, e endereços só no **domínio de teste em rota nula**. Normativa: `schematize-engineering` → `references/efeitos-externos.md`; recorte desta linguagem em `references/iam.md` §3.1; anti-padrão §37 *"Disparar efeito externo REAL a partir de não-produção"* (citado **por título**, porque a numeração do §37 diverge entre skills)

> Os itens em negrito são **bloqueantes absolutos**: archive (§28), ausência de macaquice (§37), **nenhum efeito externo real fora de `prd`** (`schematize-engineering` → `references/efeitos-externos.md`), teste emulado por IA com rota 100% acessível (ver a `schematize-qa`, `references/categorias.md` §§5 e 10), e pentest de entrada limpo (ver a `schematize-pentest`). Faltando qualquer um, a task **não está pronta** — independente de todo o resto estar verde. Smoke verde não basta: tem que ser smoke que **prova** conteúdo, não só status.

## 39. Índice de Funcionalidades (fonte da verdade viva)

**MUST — existência e localização**

- Todo projeto mantém o índice versionado em `<project>_archive/index/` (ou `/docs/index/`), em **dois níveis**:
  - **Índice global da aplicação** (`INDEX_GLOBAL.md`) — o mapa macro: repos/serviços/bounded contexts e como se comunicam; a relação de **pastas top-level** de cada repo e a responsabilidade de cada uma; **o que cada coisa faz** e o ponto de entrada de **como se faz** (link pro fluxo/use-case/runbook). É o "mapa do território".
  - **Índice de microfunções** (`INDEX_FUNCTIONS.md`, por serviço) — o catálogo fino: cada função/módulo relevante → **o quê**, **onde é usada/prevista**, dependências e efeitos colaterais. Gerado a partir dos doc-comments obrigatórios (§6).

- Todo PR que **adiciona, remove ou move** funcionalidade atualiza o índice no mesmo PR. Índice desatualizado **trava o merge** (item da DoD, §35).

- O índice é **fonte da verdade**: ao planejar uma feature, consulte-o primeiro pra não reimplementar o que já existe (anti-duplicação — liga com DRY semântico, §1).

- Formato **machine-friendly** (markdown com tabelas, ou JSON/YAML que renderiza) pra permitir geração e validação automáticas — não prosa solta.

- O índice de microfunções é **exaustivo**: **uma entrada por unidade chamável** — função, método, handler, hook, closure nomeada, job/consumer — de **cada** serviço/repo do sistema, **pública e privada**. Não existe função "irrelevante": se está no código, está no índice. "Função relevante" **não é filtro** pra pular nada.

- **Invariante verificável (conte, não confie):** por serviço, `nº de entradas no índice == nº de funções declaradas no código`. O `/<slug>-index` e o CI **contam as declarações** (AST/ctags, ou regex de `func `/`fn `/`def `/`function `/métodos) e **reprovam** se o índice tiver **menos** entradas que funções encontradas — listando as que faltam **pelo nome**. Índice com 90 linhas para 100+ funções é **falha dura**, não aviso. O mapa não "resume" o sistema; ele **enumera** o sistema.

- **Cobertura total:** o índice **global** lista **cada** microserviço/repo (nenhum de fora); cada microserviço tem seu índice de funções **completo**. Um sistema de N serviços com M funções tem os N serviços mapeados e as M funções indexadas.

**MUST — o mapa é um GRAFO, não uma lista**

- O índice/MAPA carrega um **grafo textual** de dependências, navegável em dois níveis:
  - **Grafo de serviços** (cross-service): nós = microserviços; arestas `A → B` rotuladas pelo **contrato** (rota/evento/fila/tópico). Quem chama/notifica quem no sistema inteiro.
  - **Grafo de chamadas** (intra-service): por função, **quem ela chama** (out) e **quem a chama** (in) — adjacência `chamador → chamada`. Percorre-se de um ponto de entrada até a saída, e vê-se o **raio de impacto** de qualquer função.

- **Formato:** bloco **Mermaid** (`flowchart`) — textual **e** renderiza no GitHub/markdown — **mais** a adjacência em lista/tabela (pra diff, busca e grep). O Mermaid é o desenho; a adjacência é a fonte pesquisável. Ambos gerados pelo `/<slug>-index`.

- O índice de microfunções é **gerado por script** que varre os doc-comments padronizados (§6) e monta a tabela `função → o quê → onde → arquivo:linha`. CI compara o índice commitado com o gerado; divergência aponta índice ou comentário desatualizado.

- Cada entrada linka pro arquivo/linha de origem.

- Índice global revisado em cada mudança arquitetural (junto com o ADR, §27).

**Conteúdo mínimo**

`INDEX_GLOBAL.md`: lista de repos/serviços com 1 linha de propósito cada; por repo, árvore de pastas top-level com responsabilidade; mapa de comunicação (quem chama quem, quais eventos/contratos); links pra OpenAPI, SLO, runbook.

`INDEX_FUNCTIONS.md` (por serviço, **exaustivo — uma linha por função**): `função | o quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | efeitos | arquivo:linha`; **nº de linhas == nº de funções do serviço**. Acompanha o **grafo de chamadas** (Mermaid + adjacência). O `INDEX_GLOBAL.md` inclui o **grafo de serviços** (Mermaid) com **todos** os microserviços e seus contratos.

> O índice responde "isso já existe? onde? como faço X?" sem precisar reler o código. Se a resposta exige caçar no código, o índice falhou — ou está desatualizado, e isso é bug.

## Anexo A — Versões correntes → **`references/stack-versoes.md`**

> **Esta tabela foi REMOVIDA daqui.** Versão de terceiro é **fato com prazo de validade**, e ela
> vivia clonada em 8 `entrega.md` do catálogo — a mesma tabela, com a mesma data, apodrecendo em
> oito lugares ao mesmo tempo (ela ainda apontava uma versão de Go e uma de Kubernetes que **já estavam fora de suporte**). Fato volátil tem **um** lugar por skill: o **anexo volátil**, com **data de
> verificação** e cadência de revisão.
>
> **Onde está agora:** `references/stack-versoes.md` desta skill (versões de Go e do
> ferramental dela) e, para o que é de infraestrutura (Kubernetes, Postgres, Redis, OTel), a
> **`schematize-infra`**.
>
> **A regra que fica:** mudança de versão **major** exige ADR — isso não é volátil e continua aqui.
> E o lint do catálogo (`tools/lint.mjs`, regra `anexo-volatil`) **reprova** versão cravada no
> corpo normativo quando a skill tem anexo: é o detector que impede a próxima safra.
