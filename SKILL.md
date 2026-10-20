---
name: schematize-go
metadata:
  version: 1.14.1
description: >-
  Backend em Go: arquitetura, IAM, testes, dados, deploy. Use ao projetar ou revisar go.mod, *.go, golangci-lint: serviço, API, worker, CI. Entra por fit + ADR.
---

# Padrões de Engenharia da Casa — recorte Go

Conjunto normativo que rege como software é projetado, construído, testado e operado aqui. Esta skill existe para que toda entrega — humana ou assistida por IA — siga os mesmos padrões de clareza, segurança e observabilidade, sem reinventar nem cortar caminho.

**Versão:** skill `schematize-go` v1.14.1. Changelog em `CHANGELOG.md`.

## Precedência e herança (leia antes de divergir)

<!-- herdado:engineering/precedencia:backend linguagem="Go" -->Esta skill é o **recorte Go** da base. Duas regras governam a relação, e elas resolvem sozinhas
quase toda dúvida de "onde está escrito o quê":

1. **Onde esta skill divergir da base, a BASE MANDA.** `schematize-engineering` é a normativa; aqui
   mora a **especialização** — o mecanismo, a lib, a sintaxe, o gate da linguagem. Divergência de
   *piso* entre este arquivo e a base é **defeito desta skill**, não uma variante local aceitável.
   Achou uma? É item de correção, não licença. *(Foi assim que o `argon2id-only` da casa virou
   "argon2id ou PBKDF2" em uma skill só, e o rol de 6 linguagens virou "só Go e Rust" em três.)*
2. **O que não está repetido aqui é HERDADO, não dispensado.** A ausência de um piso neste repo
   nunca significa que ele não vale — significa que ele não muda de forma nesta linguagem. Em
   especial, valem integralmente, sem cópia local:
   - **§28 Archive** — `<projeto>/<projeto>_archive/` é **repositório git próprio, PRIVADO e
     obrigatório**, criticidade 0 (`schematize-archive`; ADR-0005 para a planta canônica).
   - **§39 Índice/MAPA** — enumeração exaustiva (uma entrada por unidade chamável, `M == N`) e o
     **grafo com arestas em ASCII (`A -> B`), NUNCA a seta unicode** — o parser do app lê ASCII.
   - **§35 Definition of Done** e a lista de anti-padrões **§37** (citada por **título**, nunca por
     número: a numeração dos itens diverge entre skills).
   - **IAM** (`schematize-engineering` → `references/iam.md`): identidade ≠ email, ≥2 fatores, ReBAC multi-tenant,
     **alcançabilidade do 2º fator** (o fator de recuperação tem de ser alcançável quando o
     principal cai — senão o 2FA vira bug de bootstrap que tranca o dono para fora), os parâmetros
     mínimos de argon2id, sessão longa e logout irreversível.
   - **Rol sancionado** — Go, Rust, Elixir, C#, Zig, Ruby, por **fit + ADR**
     (`schematize-engineering` → `references/linguagens.md`). Esta skill é **uma** delas, não a
     régua das outras.
   - **Efeito externo** nunca sai de não-produção (`schematize-engineering` →
     `references/efeitos-externos.md`; gate em `scripts/check-external-effects.sh`, distribuído
     aqui — ADR-0008).<!-- /herdado -->

## Comandos (Claude Code)

Digite `/go-help` pra ver todos. Em resumo:

| Comando | O que faz |
|---|---|
| `/go-help` | lista todos os comandos do schematize-go |
| `/go-load` | carrega à força TODO o corpo normativo no contexto e passa a aplicá-lo no projeto atual |
| `/go-claude` | cria ou atualiza (com backup) o `CLAUDE.md` da raiz; mescla/avisa se detectar `CLAUDE.md` de outra skill |
| `/go-cc` | context compact: gera context.md + checklist.md no archive e roda `/compact` |
| `/go-handoff` | gera o handoff (context.md + checklist.md) **sem** compactar — pra fim de sessão |
| `/go-qa` | Q.A. no contexto Go — wrapper fino da skill **schematize-qa** (`/qa-plan` → `/qa-run`) com `go test -race` |
| `/go-review` | roda o gate da DoD/§37 no diff (arquivo >750 bloqueia / >300 úteis flag, função sem doc, índice, macaquices) |
| `/go-iam` | força/audita/scaffolda o IAM (identidade≠email, ≥2 fatores, ReBAC multi-tenant, sessão longa/logout irreversível) como microserviço Go separado em `auth.<domain>`, ou porta um auth legado |
| `/go-index` | (re)gera o índice de microfunções (§39) a partir dos doc-comments |
| `/go-ops` | audita/scaffolda o `<projeto>_ops` (interface única): fluxo de ambientes, instalação paralela (`nproc`), independência |

Os comandos ficam em `assets/commands/` e são instalados em `.claude/commands/`.

## Como usar esta skill

1. Identifique o domínio da tarefa e **leia o(s) reference(s) relevante(s)** antes de produzir código ou decisão. Não trabalhe de memória — os detalhes (versões, limites, convenções) estão nos arquivos.
2. **Sempre** aplique os pisos inegociáveis abaixo, independente do reference carregado.
3. Ao terminar, valide contra a Definition of Done (`references/entrega.md`, §35) e **gere o archive** (§28, `references/operacao.md`).

Mapa de references — leia o que casa com a tarefa:

| Tarefa | Reference |
|---|---|
| **Limites de código (arquivo ≤750: ~500 úteis + ~250 comentário; flag >300 úteis), uma função/arquivo, comentários, MAPA** | `references/padroes-codigo.md` |
| Arquitetura, camadas, DDD, repositórios, anti-monólito, shared libs, linguagens, CQRS | `references/arquitetura.md` |
| Eventos/mensageria, banco, cache, APIs, resiliência, jobs | `references/dados-eventos.md` |
| Segurança, auth, JWT, multi-tenancy, LGPD, segredos | `references/seguranca.md` |
| **IAM (identidade+autorização): auth como microserviço Go separado (`auth.<domain>`), ID≠email, ≥2 fatores/passkey/Resend/Twilio, ReBAC multi-tenant, sessão longa/logout irreversível, migração de legado** | `references/iam.md` |
| **Efeito externo fora de prd (e-mail/SMS/push/webhook): `EmailProvider` + sink default + guard decorator com `error` + cap atômico, e o teste que espera a recusa** | `references/iam.md` (§3.1) |
| **Cadeia de suprimentos: lockfile, SBOM, scan que trava, imagem mínima/pinada/assinada, SLSA, segredo no build** | `references/cadeia-suprimentos.md` |
| **Concorrência em Go: `context`, `errgroup`, cancelamento, goroutine leak (`goleak`), race detector, `sync` vs canais, `testing/synctest`** | `references/concorrencia.md` |
| Testes — o recorte Go (runner, sintaxe, armadilhas do dialeto). **A disciplina é da `schematize-qa`.** | `references/testes.md` |
| Observabilidade, healthchecks, performance, FinOps | `references/observabilidade.md` |
| Config, deploy/K8s, git/PR, ownership, runbooks/incidentes, ADR, **archive** (§20–28) | `references/operacao.md` |
| **Ops (control plane): fluxo dev→local→github→hml→prd (nada direto no servidor), ops como interface única (100%, autônomo), instalação paralela=`nproc`, independência=invariante** | `references/ops.md` |
| Templates, feature flags, IA assistida, DoD, evolução, índice de funcionalidades (§29+) | `references/entrega.md` |
| Filosofia, aplicação universal e a lista completa de anti-padrões vetados | `references/anti-padroes.md` |
| Gestão de contexto em sessões longas no Claude Code (handoff, hooks) | `references/contexto-claude-code.md` |
| Versões e limiares voláteis (linha de Go suportada, ferramental, imagem base) | `references/stack-versoes.md` |

## Pisos inegociáveis (VETADO — sem ADR de exceção)

Estes nunca são violados, nem "pra funcionar", nem "pra ir mais rápido". A lista completa com veto + caminho certo está em `references/anti-padroes.md` (§37). Os que mais aparecem em código gerado às pressas:

- **Segredo nunca no cliente.** Nada de API key, secret de JWT, senha de banco, service-role key ou token em bundle do browser nem em variável pública de build. Segredo só server-side (secret manager, injetado no processo). Detalhe em `references/seguranca.md`.
- **SQL sempre parametrizado.** Concatenar string em query é injeção esperando acontecer.
- **Auth e autorização server-side.** `tenant_id`/role/`user_id` vêm do token verificado, nunca do body/header do cliente. Validação no front é UX, não controle.
- **JWT validado por inteiro** (assinatura, exp, aud, iss, alg em allowlist). Senha nova em **argon2id** (`golang.org/x/crypto/argon2`, parâmetros mínimos e rehash de legado em `schematize-engineering` → `references/iam.md`); bcrypt/PBKDF2 só como legado a migrar no próximo login. Token/id de sessão por CSPRNG (`crypto/rand`), nunca `math/rand`.
- **Erro nunca engolido** (`_ = err`, `if err != nil { }` vazio, `recover()` que cala); sem `//nolint` sem justificativa, `panic` fora de `main`/init, nem `interface{}`/`any` + type assertion sem checar (`v, ok :=`) só pra calar o compilador. Erros embrulhados com `%w` e inspecionados com `errors.Is`/`errors.As`.
- **Teste nunca silenciado** pra passar CI (`t.Skip`, comentar assert, baixar threshold de cobertura, tirar `-race`). Conserta o código, não o teste.
- **Sem monólito que mistura bounded contexts**, sem monólito distribuído, sem shared lib `commons` de domínio. Detalhe em `references/arquitetura.md`.
- **Archive SEMPRE gerado.** Toda entrega que produz código/decisão/mudança de estado gera o `.md` de archive (§28) — é parte da entrega, não extra. Pular é violação direta. Templates em `assets/`.
- **Migration reversível** (com `down`, testada com rollback). Container não-root, read-only. Dependência nova com nome/licença/versão verificados (typosquatting é real).
- **Pisos de código (`references/padroes-codigo.md`):** arquivos **≤ 750 linhas** (teto duro: ~250 de comentário + ~500 de código útil; acima → quebrar por coesão), **flag em > 300 linhas de código útil** (não bloqueia, mas sempre sinaliza — indício de função extensa/falta de abstração, revê depois; observabilidade ~400), **uma função/unidade lógica por arquivo**, **toda função com doc-comment** (motivo, comportamento esperado, entradas, saídas, efeitos), **`MAPA.md` da aplicação** atualizado no mesmo PR — em **`<projeto>_archive/index/`, nunca no root** — e **índice de microfunções** regenerado (`/go-index`). **Todo MD gerado (MAPA/índice/plano/relatório/handoff) mora no archive**, root limpo (§28). Detalhe também em `references/arquitetura.md` (§6) e `schematize-engineering` -> `references/operacao.md` (§28, §39).
- **Backend novo só no ROL sancionado (Go/Rust/Elixir/C#/Zig/Ruby), escolhido por fit + ADR** (`schematize-engineering` → `references/linguagens.md`). Esta skill é o recorte Go, não a régua das outras. **Node como serviço backend e PHP são legado/fora do rol** — não recebem serviço novo; migração medida por funcionalidade do módulo (~30% afetado → extrai; ~50% extraído → continua extraindo até apagar o legado); PHP migra por funcionalidade quando tocado. **Frontend Node é 100% permitido** (só frontend, `schematize-web`). Detalhe em `references/arquitetura.md` (§3).
- **Fluxo de ambientes e ops (`references/ops.md`).** <!-- herdado:engineering/fluxo-ambientes:corpo -->Toda mudança segue **dev local → teste local → GitHub → hml → prd**; **VETADO editar código direto no servidor** (hml/prd é imutável por edição manual, recebe só artefato do git). **100%** das operações no servidor (install/update/correção/config/migrate/rollback) passam pela **ferramenta do `<projeto>_ops`** — nunca à mão; o ops é **autônomo** (o usuário provisiona o servidor do zero sem a IA). **Instalação sempre paralela** = `nproc`; **falha no paralelo = serviços não independentes → corrigir a independência é prioridade máxima** (não serializar pra mascarar).<!-- /herdado -->
- **Deploy destrutivo por seed + isolamento por usuário (`schematize-engineering` -> `references/ops.md` §2–§3).** <!-- herdado:engineering/deploy-destrutivo:corpo -->O ops provisiona em **`/<app>/`** clonando os repos dentro; **`/<app>/.env` é o seeder global** (fonte única de config). **Todo redeploy é destrutivo na aplicação** — apaga a anterior e recria um clone zerado só com o seed (idempotente/sem drift), **preservando os dados** (migration reversível; `ops reset` de dados só em dev/hml). **Cada serviço roda como user Linux próprio em systemd unit hardened** (blast radius mínimo). Tudo automatizado pelo ops.<!-- /herdado -->
- **IAM por desenho (`references/iam.md`).** Todo projeto começa com identidade+autorização robustas, e o **auth é app SEPARADA** — **microserviço Go** `<projeto>_auth_go` + front próprio em `auth.<domain>`, isolados; nunca monolith (nem `internal/auth`); apps delegam por OIDC/PKCE e validam por JWKS público. Providers (e-mail OTP Resend, Twilio) como interfaces Go; PEP=middleware Go. <!-- herdado:engineering/iam-desenho:invariantes cmd="go" -->**ID interno imutável (ULID/UUIDv7) — email/telefone nunca é ID** (N emails por usuário; SSO com recuperação local). **≥2 fatores sempre**: passkey/WebAuthn no núcleo, TOTP/push, email OTP always-on, Twilio para telefone; senha argon2id+HIBP por padrão, mas opcional; invariante de troca de fator (Y≠X no maior AAL); **recuperação ≥ login**. Senha + Email OTP já é **2FA baseline**: o PEP libera o baseline e exige AAL alto **só por rota sensível** (step-up just-in-time), nunca barra o login. **Multi-tenant RBAC/ABAC granular via ReBAC** (OpenFGA/SpiceDB; deny-default, PDP=Check API, PEP no servidor, token fino). **Multi-dispositivo, sessão 7d/90d, logout irreversível** (revoga refresh+família, `jti` na denylist, não só cookie). **Passkey/WebAuthn é o método PADRÃO e entra na FASE 0** (registro+asserção reais e2e antes de qualquer feature; passwordless-first, senha+Email OTP fica de fallback/2FA baseline; teste: registro, login, challenge reutilizado, origin/rpId errado e credencial revogada rejeitados) — a implementação mora no IAM da casa (`auth.<domínio>`), o app cliente só integra via OIDC/PKCE. **Toda rota exposta nasce com teste de matriz de acesso no CI** (anônimo/não privilegiado/privilegiado/burlas; status e corpo; deny-by-default; inventário derivado, M == N) — detalhe na `schematize-qa` (`scripts/check-route-authz.sh`). **Migrar auth legado = prioridade 0.** Scaffold/auditoria por **`/go-iam`**; testes cross-tenant/priv-esc na `schematize-pentest`.<!-- /herdado -->
- **Efeito externo NUNCA sai de não-produção (`references/iam.md` §3.1; normativa na `schematize-engineering` → `references/efeitos-externos.md`).** E-mail, SMS/voz, push, webhook de terceiro e cobrança **não acontecem de verdade** fora de `prd` — por construção, não por lembrança. Em Go: **`EmailProvider` já é interface (§3)**, então o **provider default fora de prd é o `SinkProvider`** (Mailpit/`log/slog`) e o **guard é um decorator da própria interface** (`mail.Guarded(p, env, testDomains, cap)`), embrulhado **na composição (`main.go`), nunca no chamador** — destinatário fora do domínio de teste com `env != prd` devolve **`error`** (`ErrExternalRecipientBlocked`), nunca `slog.Warn` nem `nil` (casa com "erro nunca engolido"); `ParseEnv` sem valor declarado assume **não-prd**, `cap <= 0` cai no default 50 e o cap usa `atomic.Int64`. Provado por **`TestGuard_RecusaDominioExterno`** (espera o erro; nenhum byte sai). <!-- herdado:engineering/efeito-externo:invariantes -->**Cap por execução** (`MAIL_MAX_PER_RUN`, default 50) com abort; **fail-closed** (ambiente ausente/desconhecido ⇒ não-prd; só o valor exato de produção entrega de verdade); **chave sandbox** fora de prd. Todo endereço sintético (fixture, seed, persona, demo, carga) é `<papel>+<run-id>-<n>@test.<domain>` — domínio em **rota nula** (null MX RFC 7505 + SPF `-all` + DMARC `p=reject`) ou TLD reservado (`.test`/`.invalid`/`.example`); **VETADO** `@gmail.com`, domínio de cliente/terceiro, e-mail de pessoa real (**inclusive o seu**) e o domínio de produção. A recusa é **erro**, nunca warning nem sucesso silencioso. Entregar de verdade fora de prd exige **as cinco** (ADR + allowlist ≤5 + cap + janela + subdomínio separado). Motivo: bounce/complaint em massa **queima IP e domínio** e derruba o transacional de prd — inclusive o **OTP de login** — com semanas de warm-up e utilidade zero (o incidente dos 5.000 e-mails só existiu porque nada contava).<!-- /herdado -->
- <!-- herdado:engineering/orquestracao:bullet -->**Orquestrador não desenvolve; subagent barato executa** (`schematize-engineering` → `references/orquestracao.md` §9). O principal só planeja/decompõe/despacha/supervisiona/revisa; ação onerosa vira micro-tasks; principal = Claude Opus; executor mais barato que resolve: `haiku` (mecânico) / `sonnet` (código, até 2 rodadas de correção pelo mesmo subagent) → Codex `gpt-5.6-terra` → Cursor → subagent `opus` (motivo no checkpoint) → `park`; **visual direto ao Codex; imagem nunca pelo Claude (pergunta ao usuário: Codex sugerido, ou Gemini), API de imagem paga PROIBIDA**; papéis configuráveis em `agentes.toml` (aba "Agentes" do overdev). No `overdev`, cada item do checklist é executado pelo papel adequado e revisado pelo principal (diff + gate) antes do `- [x]`. **Sem frota ociosa:** agent idle com pendência executável volta ao trabalho; pendência que depende de outro agent → mata e enfileira com gatilho de dependência; terminou → mata (§9.6).<!-- /herdado -->

> Regra de bolso: se a justificativa começa com "só pra funcionar", "depois eu arrumo" ou "é mais rápido assim" e o resultado mexe em segredo, auth, dado ou registro — é um anti-padrão vetado. Pare e faça certo.

## Testes — o que conta como "verde de verdade"

Detalhe em `references/testes.md` (o recorte Go) — a **disciplina** de teste é da `schematize-qa`, e a segurança ofensiva da `schematize-pentest`.

- **Smoke não pode ser teatro:** assertar shape do body (não só status 200), assertion negativa (sem stack trace/placeholder), e um **self-check que força uma falha conhecida** pra provar que o runner consegue reportar FAIL. Smoke que nunca falha está cego.
- **Unit agressivo:** caminho de erro obrigatório, casos hostis (tipo errado, unicode, null byte, boundary), property-based e mutation testing no domínio crítico. Cobertura de linha é piso, não meta.
- **Pentest prova rejeição, rota por rota, campo por campo:** nunca 500 por input hostil, nunca coerção silenciosa de tipo (varchar onde é int), nunca eco sem escape, nunca vazamento cross-tenant. Princípios em a `schematize-pentest`).
- **`simulated` (teste emulado):** cruza rotas × personas × injections e prova que **100% das rotas** do inventário estão acessíveis pra quem deve e bloqueadas pra quem não deve. Rota fantasma/morta quebra o run.
- **Fluxo de Q.A. (plan-first):** a disciplina de Q.A. plan-first da casa foi extraída para a skill dedicada **schematize-qa** (`/qa-plan` → `/qa-run`): planeja tudo primeiro, gera o MD de passo a passo, **pede aprovação antes de executar**, roda faseado/assistido ou de uma vez com watchdog (sem retry infinito, passo destrutivo só com gate), coleta `summary.json` e trava nos gates. `/go-qa` é o wrapper de contexto Go (`go test -race`). Nada de Q.A. roda às cegas.

## Andaime pronto (scripts e templates)

Não escreva do zero o que já está bundlado:

- `scripts/lib.sh` — helpers de teste (`test_pass`, `test_fail`, `test_skip`, `test_section`, `test_summary`, `http_call`, `assert_http_in`). Todo script de teste usa estes.
- `scripts/test-skeleton.sh` — esqueleto obrigatório de `tests/<mode>/<name>.sh`.
- `scripts/smoke-selfcheck.sh` — o meta-teste anti "verde mentiroso".
- `scripts/simulated/run.py` — scaffold do engine rotas × personas × injections.
- `scripts/hooks/context-monitor.mjs` + `scripts/hooks/precompact-backup.mjs` — gestão de contexto no Claude Code: detectam o limite de handoff (default 250k) e fazem backup automático em `<projeto>_archive` antes da compactação. Ver `references/contexto-claude-code.md` e `assets/settings.claude.example.json`.
- `assets/ADR.md`, `assets/TASK.md`, `assets/CHAT_ARCHIVE.md`, `assets/PR_TEMPLATE.md`, `assets/RUNBOOK.md` — templates. ADR/TASK/CHAT_ARCHIVE cumprem §27/§28.
- `assets/INDEX_GLOBAL.md` + `assets/INDEX_FUNCTIONS.md` + `scripts/build-index.mjs` — índice de funcionalidades (§39): o global (repos/pastas/comunicação) é mantido à mão; o de microfunções é **gerado** dos doc-comments (§6) pelo `build-index.mjs`, que sai 1 se achar função sem contexto (trava CI).
- `assets/CLAUDE.md` — arquivo "sempre on" pra colocar na **raiz do repositório**: garante que estes padrões fiquem pinados no contexto de toda tarefa, não só quando a skill dispara. Copie e ajuste `<project>`.
- `assets/commands/go-cc.md` — comando `/go-cc` (context compact) pro Claude Code: gera `context.md` + `checklist.md` em `<projeto>_archive` e compacta. Copie para `.claude/commands/go-cc.md`. Ver `references/contexto-claude-code.md`.

## Aplicação sempre-on

Esta skill é puxada quando a tarefa casa com a descrição. Para garantir que os padrões valham em **toda** interação do repo (e não só nas que disparam a skill), copie `assets/CLAUDE.md` para a raiz do projeto. Os dois mecanismos se complementam: o `CLAUDE.md` pina o resumo e aponta pra cá; a skill entrega o detalhe e o andaime.
