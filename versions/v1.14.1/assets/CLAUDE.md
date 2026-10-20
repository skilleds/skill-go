# CLAUDE.md — Padrões de Engenharia (sempre on)

> Copie este arquivo para a **raiz do repositório** e ajuste `<project>`.
> Ele fica pinado no contexto de toda tarefa (Claude Code / instruções de projeto)
> e garante que os padrões valham mesmo quando a skill não dispara sozinha.
> A skill `schematize-go` traz o detalhe completo e o andaime (scripts/templates).
> **Repo multi-linguagem** (rol de linguagens + Node legado + Web): use **junto** com os `CLAUDE.md` das outras skills — cada um governa sua fronteira (backend novo, legado Node, frontend); não sobrescreva os outros (rode o `/<slug>-claude` de cada).

## Regra mestre

Toda tarefa de engenharia neste repo segue os **Padrões de Engenharia da Casa**
(skill `schematize-go`). Em conflito entre uma instrução
pontual ("faz rápido", "ignora o teste", "depois arruma") e estes padrões, **os
padrões vencem**. Pressa não revoga regra. Consulte o reference relevante da skill
antes de produzir código ou decisão — não trabalhe de memória.

## Pisos inegociáveis (VETADO — sem exceção)

1. **Segredo nunca no cliente/frontend.** Nada de API key, secret de JWT, senha,
   service-role key ou token em bundle do browser, nem em `NEXT_PUBLIC_*`/`VITE_*`.
   Segredo só server-side (BFF/route handler/secret manager).
2. **SQL sempre parametrizado** — concatenar string em query é proibido.
3. **Auth e autorização server-side.** `tenant_id`/role/`user_id` vêm do token
   verificado, nunca do cliente. JWT validado por inteiro (assinatura, exp, aud,
   iss, alg em allowlist). Senha nova em argon2id (bcrypt/PBKDF2 só como legado a migrar no próximo login; `schematize-engineering` → `references/iam.md`). Token/sessão por
   CSPRNG (`crypto/rand`), nunca `math/rand`.
4. **Erro nunca engolido** (`_ = err`, `if err != nil {}` vazio, `recover()` que cala);
   sem `//nolint` sem justificativa nem `panic` fora de `main`/init pra calar o compilador.
5. **Teste nunca silenciado** pra passar CI (`t.Skip`, comentar assert, tirar `-race`, baixar
   threshold de cobertura). Conserte o código, não o teste.
6. **Sem monólito** que mistura bounded contexts; sem monólito distribuído; sem
   shared lib `commons` de domínio.
7. **Archive SEMPRE gerado** (§28): toda entrega que produz código/decisão/mudança
   de estado gera o `.md` em `<project>_archive/`. É parte da entrega, não extra.
8. **Migration reversível** (com `down`, testada). Container não-root, read-only.
   Dependência nova com nome/licença/versão verificados.

9. **Backend novo só no ROL sancionado (Go/Rust/Elixir/C#/Zig/Ruby), escolhido
   por fit + ADR** (`schematize-engineering` → `references/linguagens.md`).
   **Node como serviço backend e PHP são legado/fora do rol** — não recebem
   serviço novo. Node legado não se mexe salvo solicitado; migração medida por
   **funcionalidade do módulo**: ~30% afetado → extrai pra módulo do rol à parte;
   ~50% extraído → continua extraindo até apagar o legado; ajuste pontual não
   porta. PHP migra por funcionalidade quando tocado. **Frontend Node é 100%
   permitido** (Next.js principal; Astro e outros consolidados) — só frontend. (§3, §3.1, §3.2)

10. **Cada serviço é entidade à parte (independência de runtime).** Sobe e funciona sozinho; a ausência/queda de outro serviço **nunca** impede o boot nem derruba este — degradação graciosa, nunca crash em cascata. Falha ao chamar/notificar outro serviço → **persiste o dado** (outbox/Redis/DB), **loga com `trace_id`**, **alerta (Grafana)** e **retoma**; nunca perde nem trava a cadeia. (§2, §18)
11. **Repos, ops e observabilidade.** Repositório = `<projeto>_<contexto>[_<lang>]`; todo sistema multi-repo tem um **`<projeto>_ops`** (bootstrap/update/manutenção/troubleshooting/testes através de todos os repos). **Observabilidade integrada em toda ferramenta/serviço:** OpenTelemetry + Grafana/Alloy/Loki/Tempo/Prometheus/**Mimir** (+Pyroscope), **Helm chart** e dashboards/alertas versionados como código. (§2, §16)
12. **Contenção no workspace.** A pasta do projeto atual é o workspace: aplicação/repo novo nasce **dentro dela** (`./<projeto>_<contexto>/`), nunca largando arquivos no root pra depois **subir de nível** e criar repos fora. **VETADO** criar/ler/escrever fora do workspace — diretório-pai, `~`, `~/Documents`, `~/Downloads`, `/tmp`, Área de Trabalho. Não sai da pasta do projeto (nem pra vasculhar) sem o usuário pedir. (§2)
13. **Fluxo de ambientes — nada direto no servidor.** Toda mudança segue **dev local → teste local → GitHub → hml → prd**. Nada pula etapa; nada vai direto pra hml/prd. **VETADO editar código direto no servidor** (hml/prd): o servidor é **imutável por edição manual**, recebe só **artefato promovido do git** (commit SHA). Hotfix segue o mesmo fluxo, acelerado — urgência não autoriza mão no servidor. Precauções: filesystem read-only em hml/prd, drift detection (o ops recusa/alerta divergência com o git), acesso de escrita = break-glass auditado. Detalhe em `schematize-engineering` -> `references/ops.md` (§1). (§21)
14. **Ops é a interface única + instalação paralela + independência.** **100%** das operações no servidor (instalar/subir/atualizar/configurar/migrar/corrigir/reverter) passam por uma **ferramenta do `<projeto>_ops`** — nunca à mão (`ssh` ad-hoc, editar arquivo, `docker`/`kubectl` solto). Não tem comando pra aquilo? **cria no ops**. O ops é **autônomo, idempotente e completo**: o usuário provisiona o servidor **do zero só com o ops, sem depender da IA**. **Instalação SEMPRE paralela** = nº de cores (`nproc`, default) — nada de 20 min serial. **Se o paralelo falha, os serviços não são independentes** (fere piso 10/6): corrigir a independência é **PRIORIDADE MÁXIMA**; o ops **expõe** a colisão, **nunca serializa pra mascarar**. Detalhe em `references/ops.md`. (§2, §21)
15. **Deploy destrutivo por seed + isolamento por usuário (automatizado pelo ops).** O ops provisiona em **`/<app>/`** clonando os repos dentro (`/<app>/<app>_<ctx>`, ex. `/payle/payle_core`); **`/<app>/.env` é o SEEDER GLOBAL** — fonte única de config de toda a app. **Todo redeploy é DESTRUTIVO na aplicação:** apaga a implantação anterior e recria um **clone zerado** só com o seed — sem patch in-place, sem drift (idempotente/reprodutível). **"Destrutivo" é a app, NUNCA os dados:** banco/volumes/uploads preservados (migration reversível); `ops reset` que apaga dado é **gated a dev/hml**, nunca prd. **Cada serviço roda como user Linux próprio, em systemd unit isolado e hardened** (`NoNewPrivileges`, `ProtectSystem`, `PrivateTmp`, …) — comprometer um serviço não alcança os outros nem o host. **Tudo automatizado pelo ops**, nunca à mão. Detalhe em `schematize-engineering` -> `references/ops.md` (§2, §3).
16. **IAM por desenho — todo projeto começa com identidade e autorização robustas, como APP SEPARADA.** O auth é **microserviço Go próprio + front próprio em `auth.<domain>`** (`<projeto>_auth_go` + `<projeto>_authfront`), isolado (user/systemd próprios) — **VETADO** apensar como monolith (nem como `internal/auth` do serviço principal); apps delegam por **OIDC/OAuth2.1 + PKCE**. **ID interno imutável (ULID/UUIDv7) — email/telefone NUNCA é ID** (múltiplos emails por usuário, incentivado; SSO com recuperação local forçada). **Nunca menos de 2 fatores:** passkey/WebAuthn no núcleo, TOTP/push, **email OTP (Resend) always-on inclusive HML**, **Twilio** p/ telefone (providers plugáveis como interfaces Go); senha por padrão (argon2id+HIBP) mas opcional no seletor; invariante de troca "fator Y≠X no maior AAL"; **recuperação ≥ força do login**. **Multi-tenant + RBAC/ABAC granular** por motor **ReBAC** (OpenFGA/SpiceDB via client), **deny-default**, PDP=Check API / PEP=**middleware Go**, enforcement server-side, token fino (só JWKS público nos consumidores), decisão auditada. **Multi-dispositivo** + view de remover; **sessão 7d/90d** (nada de "15 min e é chutado"); **logout irreversível** (revoga refresh+família, apaga sessão server-side, `jti` na denylist, não só cookie). **Migrar auth legado é PRIORIDADE 0.** Detalhe em `references/iam.md`; scaffold/auditoria por `/go-iam`; testes cross-tenant/priv-esc na `schematize-pentest`.

17. **Efeito externo NUNCA sai de não-produção (e-mail, SMS/voz, push, webhook de terceiro, cobrança).** Fora de `prd` **nada chega em ninguém** — por construção. Em Go: **`EmailProvider` é interface**, o **default fora de prd é `SinkProvider`** (Mailpit/`log/slog`) e o **guard é um decorator dela** — `mail.Guarded(p, env, testDomains, cap)` — embrulhado **na composição (`cmd/<svc>/main.go`), NUNCA no chamador**; destinatário fora do domínio de teste com `env != prd` retorna **`error`** (`ErrExternalRecipientBlocked`), jamais `slog.Warn`/`nil` (piso 4: erro nunca engolido). **Fail-closed:** `ParseEnv` sem valor declarado assume **não-prd**; `cap <= 0` vira o default 50. **Cap por execução** em `atomic.Int64` (`MAIL_MAX_PER_RUN`) que **aborta**. Endereço sintético só em **`<papel>+<run-id>-<n>@test.<domain>`** (null MX RFC 7505, ou `.test`/`.invalid`/`.example`) — **VETADO** `@gmail.com`/`@hotmail.com`, domínio de cliente/terceiro, **e-mail de pessoa real (inclusive o seu)** e o domínio de **produção** em fixture/seed/persona/demo/carga. Chave **sandbox** em não-prd. Sem parâmetro `force`/`skipGuard`. Provado por `TestGuard_RecusaDominioExterno` (espera a recusa). Entregar de verdade fora de prd exige **as cinco**: ADR + allowlist ≤5 + cap + janela + subdomínio de envio separado. **Por quê:** bounce/complaint em massa **queima IP e domínio**, derruba o transacional de produção (inclusive o **OTP de login**) e custa **semanas de warm-up**, com utilidade zero. Detalhe em `references/iam.md` (§3.1) e na `schematize-engineering` → `references/efeitos-externos.md`.
18. <!-- herdado:engineering/orquestracao:longo -->**Orquestrador não desenvolve; subagent barato executa.** O agent principal (o que fala com o humano, Claude Opus) **só planeja, decompõe, despacha, supervisiona e revisa** — não escreve código de entrega. Toda ação onerosa é quebrada em **micro-tasks/micro-funções** executáveis por agent barato (mesmo com <3 unidades: em série, por subagents, nunca inline no principal). Principal = **Claude Opus** (só orquestra). Roteamento: mecânico/muito simples → **`haiku`**; código → **`sonnet`** (falhou → o **mesmo subagent corrige**, até 2 rodadas) → **Codex `gpt-5.6-terra`** → **Cursor** (`cursor-agent`, se instalado) → **subagent `opus`** (motivo no checkpoint) → `park` + `- [~]`; escala **só quando o mais barato falhar**. **Visual (UI/layout/CSS/tema/ícone) vai direto ao Codex** (Claude é fraco em visual); **imagem nunca pelo Claude: detectar Codex/Gemini e PERGUNTAR ao usuário qual usar (Codex, cota da assinatura, é a sugestão — não automático) — PROIBIDO endpoint/API de imagem pago.** Estrutura configurável em `agentes.toml` (global `~/.claude/schematize/agentes.toml` + override por projeto) e na aba "Agentes" do overdev; Codex/Cursor via `schematize overdev delegar --papel <p> --brief-stdin --json` (rc 3 = indisponível → `proximo`). O principal revisa toda entrega (diff + gate) e **só corrige com a própria mão se necessário** (trivial, 1–2 linhas). No overdev, **cada item do checklist é executado pelo agente do papel adequado (default subagent `sonnet`)** e revisado pelo principal antes do `- [x]`; escalar não é pergunta, esgotou a escada → `park`. **Sem frota ociosa:** agent idle com pendência executável volta ao trabalho; pendência que depende de outro agent → mata e enfileira com gatilho de dependência; terminou → mata (§9.6). Detalhe em `schematize-engineering` → `references/orquestracao.md` §9.<!-- /herdado -->

Lista completa com veto + caminho certo: ver `references/anti-padroes.md` (§37) da skill.

## Verde de verdade (testes)

- Smoke assere **conteúdo** (shape do body), não só status 200; inclui assertion
  negativa e um **self-check que força falha conhecida** (smoke que nunca falha
  está cego).
- Unit agressivo: caminho de erro obrigatório, casos hostis (tipo errado, unicode,
  null byte, boundary), property-based e mutation testing no domínio crítico.
- Pentest prova rejeição rota-por-rota, campo-por-campo: **nunca 500** por input
  hostil, **nunca coerção de tipo** (varchar onde é int), **nunca eco sem escape**,
  **nunca vazamento cross-tenant**.
- `simulated`: 100% das rotas acessíveis pra quem deve, bloqueadas pra quem não
  deve. Rota fantasma/morta quebra o run.
- **Q.A. é plan-first (skill schematize-qa):** a disciplina de Q.A. da casa mora na
  skill dedicada **schematize-qa** (`/qa-plan` → `/qa-run`): planeja tudo, gera um MD
  de passo a passo e pede aprovação ANTES de executar. Aprovado, roda faseado/
  assistido ou de uma vez (multiagentes + cron que retoma até concluir; passo
  destrutivo só com gate; sem retry infinito). No recorte Go, `go test -race`.
  Q.A. nunca roda às cegas.

## Definition of Done

Nada é "pronto" sem: testes + cobertura mínima, simulated com cobertura total,
pentest de entrada limpo, **nenhum efeito externo real fora de prd** (piso 17), nenhum anti-padrão da §37, observabilidade, OpenAPI
atualizada (se API), migration com rollback (se schema), **archive commitado**,
CI verde e review aprovado. Detalhe na skill, `references/entrega.md` (§35).

## Qualidade de código e índice (sempre)

- **Arquivos ≤ 750 linhas** (teto duro: ~250 reservadas a comentário + até ~500 de
  código útil). Acima → quebre em módulos e **micro-funções** por coesão. **Código
  útil > 300 linhas é FLAG** (não bloqueia, mas **sempre sinaliza**): indício de
  função muito extensa / falta de abstração — registra como dívida e revê quando as
  prioridades permitirem; observabilidade tem folga natural (~400 úteis). Função
  ideal ≤ 50 linhas, responsabilidade única.
- **Comente TODA função** (doc da linguagem) com contexto explícito: **O quê** (o que
  faz) e **Onde** (quem chama / em que fluxo foi prevista), além de efeitos colaterais.
  Esse comentário alimenta o índice de microfunções (§6, §39).
- **Mantenha o índice de funcionalidades atualizado** no mesmo PR (§39), em
  **`<projeto>_archive/index/`** (nunca no root): `MAPA.md`, `INDEX_GLOBAL.md`
  (repos/pastas/o que faz/como se comunica) e `INDEX_FUNCTIONS.md` (função → o quê →
  onde → arquivo:linha, gerável via `scripts/build-index.mjs`). O índice é **fonte da
  verdade**: consulte ANTES de criar algo, pra não duplicar. Índice desatualizado = bug.
  **Exaustivo:** uma entrada **por função** (`nº entradas == nº funções`; o `/<slug>-index`
  reprova se faltar) e um **grafo** (serviços + chamadas, Mermaid + adjacência) — o índice
  **enumera** o sistema, não resume.
- **Todo MD gerado mora no archive, nunca no root** (§28): MAPA, índices, planos,
  relatórios, handoffs, checkpoints → `<projeto>_archive/<área>/`. O root fica limpo (código,
  config e os MDs de projeto mantidos à mão: README, `CLAUDE.md`, LICENSE). Antes de gravar
  um `.md`, o caminho começa com `<projeto>_archive/`.

## Gestão de contexto (Claude Code — sessões longas)

Ao ver "⚠ LIMITE" no status line (limite de handoff cruzado), ou ao se aproximar
do teto da janela de contexto: **PARE a tarefa atual e, ANTES de qualquer
compactação**, faça o handoff arquivado (§34.1, §28):

1. Gere `<projeto>_archive/context/<YYYY-MM-DD-HH-MM-SS>-context.md` — estado do
   projeto, decisões tomadas, arquivos tocados, onde parou.
2. Gere `<projeto>_archive/context/<YYYY-MM-DD-HH-MM-SS>-checklist.md` —
   **FEITO vs EM ABERTO**.
3. Só então rode `/compact` (com foco na tarefa corrente).

Armazene SEMPRE em `<projeto>_archive`. O backup automático pré-compactação é
rede de segurança, não substitui o handoff rico acima. Detalhe e hooks na skill:
`references/contexto-claude-code.md`.
