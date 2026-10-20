# Changelog — schematize-go

Todas as mudanças relevantes deste pacote, no formato [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
com versionamento [SemVer](https://semver.org/lang/pt-BR/).
## [1.14.1] — 2026-10-20
### Alterado
- Bloco herdado `engineering/iam-desenho:invariantes` sincronizado: passkey padrão na fase 0 e matriz de acesso por rota.


## [1.14.0] — 2026-10-14
Gates de script com vermelho plantado, bugs reais achados por eles corrigidos e IAM/Postgres/API apontando para as skills donas.

### Corrigido
- `test-skeleton.test.sh`/`smoke-selfcheck.test.sh`: o `trap` de limpeza vira função com `p` local (fim do SC2154); scripts no piso de shell.
- `scripts/archive-secret-scan.sh`: a regra de `password=` usava `[^ \n"']` — em ERE `\n` dentro de colchete é a letra `n`, então qualquer senha com `n` (quase todas) passava em branco. Agora `[^ "']`.
- `scripts/check-diff.sh`: a regra de CORS `*` não pegava a forma canônica `Set("Access-Control-Allow-Origin", "*")` (faltava a vírgula na classe); base inexistente (`origin/main` ausente) virava "OK" por diff vazio — agora BLOQUEIA com mensagem.

### Adicionado
- Testes com vermelho e verde plantados (segredos falsos montados em tempo de execução, repos e servidores em `mktemp`): `archive-secret-scan.test.sh`, `check-diff.test.sh` (cada regra do piso + isenções + base inválida), `smoke-selfcheck.test.sh` (inclui o runner cego: `--self-check` tem que sair 1), `test-skeleton.test.sh`. O gate `check-skill` da skill-dev exigia (`script-sem-teste`); `lib.sh` fica isento.

### Alterado
- Description reduzida a ≤190 caracteres (orçamento do catálogo com 45 skills), mesmo território.
- `references/iam.md`: topologia, fluxos, sessão, migração de legado e risco adaptativo viram piso curto + ponteiro `schematize-iam → references/*.md` (a skill dona); fica o recorte de linguagem (providers, guard de efeito externo, PEP, libs).

## [1.13.1] — 2026-10-14
Ressincronização dos blocos herdados com a engineering v0.27.0; sem mudança de piso próprio.

### Alterado
- Description reduzida (≤235 chars) para caber no orçamento de listagem de skills (soma ≤8300); mesmo território, fronteiras com as irmãs preservadas.
- Blocos herdados ressincronizados com a `schematize-engineering` v0.27.0 (`tools/sync-herdados.mjs`): orquestração com a regra de imagem (nunca pelo Claude; detecta Codex/Gemini e pergunta ao usuário qual usar, Codex como sugestão) e `schematize overdev delegar` (comando do app) no lugar do falso nome de skill `schematize-overdev`.

## [1.13.0] — 2026-10-14
Saneamento da skill: a description deixa de reivindicar "qualquer backend/frontend/infra" e o texto deixa de tratar Go como régua das irmãs.

### Adicionado
- `references/concorrencia.md`: `context`, `errgroup` (`SetLimit`), cancelamento, goroutine leak + `goleak`, race detector, `sync` vs canais, backpressure/shutdown e `testing/synctest` — o equivalente Go de `async-concorrencia.md` da skill Rust. Versões dependentes ficam em `stack-versoes.md`.
- CI: `go vet`, `golangci-lint` v2, `govulncheck` e `go test -race` (job `go-lint-test`); Trivy/Gitleaks/checkout pinados por SHA.

### Alterado
- Description reescrita (≤350 chars) ancorada em Go (`go.mod`, `*.go`, `go test`, `golangci-lint`); `skill.toml`: tag e descrições pt/en/es só de Go.
- Piso "Backend novo só em Go ou Rust; Node proibido" (`SKILL.md`, `assets/CLAUDE.md`) trocado pelo texto do rol sancionado (fit + ADR); `references/arquitetura.md` sem tabela "padrão da casa → Go", Node/PHP saem "para o rol" e PHP migra por funcionalidade quando tocado, com ponteiro para `schematize-engineering` → `references/linguagens.md`.
- Hash de senha: argon2id-only para senha nova (bcrypt/PBKDF2 só como legado a migrar), com ponteiro para `schematize-engineering` → `references/iam.md`; pisos com idioma JS/Rust (`Math.random`, `catch {}`, `@ts-ignore`, `unwrap`) trocados por equivalentes Go (`math/rand`, `_ = err`, `//nolint`).
- Tabela de comandos completa (`/go-load`, `/go-claude`); mapa de references inclui `stack-versoes.md` e `concorrencia.md`; `seguranca.md` deixa de ser anunciado como cobrindo "frontend".
- Herdados parametrizados da base (`schematize-engineering` → `assets/herdados/`): os blocos "Precedência e herança", "Fluxo de ambientes e ops", "Deploy destrutivo", "Efeito externo" e "IAM por desenho" passam a ser gerados por `tools/sync-herdados.mjs` (lead específico de cada linguagem fica fora do bloco); `references/contexto-claude-code.md` e `scripts/check-external-effects{,.test}.sh` viram arquivos herdados (convenção do archive corrigida para `<projeto>/<projeto>_archive`; só a engineering é dona do handoff). A frase do step-up (senha + Email OTP = 2FA baseline, AAL alto só por rota sensível) vira regra comum do IAM.

### Removido
- `assets/lint/eslint.layers.cjs` (config JS dentro da skill Go, sem referência).
- **Description** reduzida (~270 chars) para caber no orçamento de listagem (soma das 31 skills ≤ 8500; o Claude Code corta a listagem acima disso).
- **CI:** actions de terceiros pinadas por SHA completo com comentário `# vX.Y.Z` (mesma major em uso; supply chain), mesmo SHA em todas as skills.

## [1.12.2] — 2026-09-30
O piso de orquestração passa a ser **herdado** da base em vez de copiado à mão: uma mudança na engineering não exige mais editar 38 arquivos.

### Alterado
- Piso "Orquestrador não desenvolve; subagent barato executa" em `assets/CLAUDE.md` e `SKILL.md` agora é um bloco `<!-- herdado:engineering/orquestracao:… -->`, sincronizado de `schematize-engineering/assets/herdados/orquestracao.md` por `tools/sync-herdados.mjs` (checado no CI). Redação normalizada; conteúdo inalterado.

### Mantido (piso inalterado)
- Sonnet por default, escada até opus, sem frota ociosa (engineering `references/orquestracao.md` §9/§9.6).

## [1.12.1] — 2026-09-30
Pedido do dono: agents idle poluem a tela e seguram recurso.

### Adicionado
- Piso de orquestração ganha a regra de frota ociosa (idle com pendência volta ao trabalho; dependente de outro agent → mata e enfileira com gatilho; terminou → mata); detalhe na `schematize-engineering` §9.6.

## [1.12.0] — 2026-09-30
Orquestração por papéis e escada de modelo (custo). Pedido do dono: o orquestrador em modelo padrão não desenvolve; ações onerosas viram micro-tasks baratas; `sonnet` é o default nos subagents e `opus` só após falha.

### Adicionado
- **Piso 18 no `assets/CLAUDE.md` e bullet nos pisos do `SKILL.md`: "Orquestrador não desenvolve; subagent barato executa"** — o agent principal só planeja, decompõe, despacha, supervisiona e revisa; subagents em `sonnet` por padrão; falhou → o mesmo subagent corrige (até 2 rodadas) → re-decompõe → só então `opus`, com o motivo no checkpoint. Normativa na `schematize-engineering` → `references/orquestracao.md` §9 (não duplicada aqui).
- **Recorte overdev:** no laço, cada item do checklist é executado por subagent `sonnet` e revisado pelo principal (diff + gate) antes do `- [x]`; escalar para Opus não é pergunta, esgotou Opus → `park`.

### Mantido (piso inalterado)
- Todos os pisos anteriores (segurança, IAM, efeito externo, archive, ops) seguem como estavam; a §9 escolhe **quem executa**, não relaxa **o que** se exige. Paralelizar para o relógio continua o padrão.

## [1.11.0] — 2026-08-21
Saneamento do catálogo conforme a vistoria de 2026-08-21.

### Adicionado
- **Go moderno, onde ele muda o jeito de escrever** (`references/padroes-codigo.md`): **`iter.Seq`/range-over-func** (com `iter.Seq2[T, error]` e o motivo — o erro vai **por dentro** da sequência, matando o antipadrão de guardar o erro num campo do iterador), **`go tool`** (o fim do hack do `tools.go`: CI e dev na mesma versão da ferramenta, sem `go install` global) e **`testing/synctest`** (detalhado em `references/testes.md`), que é a resposta ao `time.Sleep(50ms)` "para dar tempo" — origem do flaky no CI carregado.
- **`govulncheck` no pipeline MUST** (`references/seguranca.md`), com o que o diferencia de um SCA qualquer: **alcançabilidade** — *SCA que lista toda CVE de toda dependência transitiva vira ruído, e ruído se ignora*.

### Corrigido
- `references/iam.md`: o parâmetro `cap` **sombreava o builtin** (com ele, `cap(slice)` fica inacessível e o compilador não reclama) → `maxPerRun`; e o body da resposta HTTP passou a ser **drenado antes de fechar**, inclusive no caminho de erro — fechar sem drenar descarta a conexão keep-alive e vira **socket churn** em volume.
- O rol de linguagens no `anti-padroes.md` dizia "backend novo só em Go/Rust" — a deriva por cópia que a vistoria chama de Classe C. Agora é o rol sancionado com ADR de fit, e **Go é o default pragmático em empate**, não o único permitido.

### Mudado
- `anti-padroes.md`, `arquitetura.md` e `entrega.md` viraram **ponteiro**: os blocos idênticos à base foram podados mecanicamente (`tools/podar-clone.mjs`), e o banner explica por que a numeração salta.

## [1.10.0] — 2026-08-20
Piso "efeito externo NUNCA sai de não-produção" no recorte **Go** — o guard idiomático, com código pronto pra copiar.

### Adicionado
- **`references/iam.md` §3.1 — "Efeito externo fora de prd — o guard mora DENTRO do provider (recorte Go)":** pacote `internal/platform/mail` completo — `Message`/`EmailProvider` (a porta), erros sentinela `ErrExternalRecipientBlocked`/`ErrRunCapExceeded` (distinguíveis por `errors.Is`), `Env` + `ParseEnv` **fail-closed** (valor ausente/desconhecido ⇒ não-prd), `SinkProvider` (Mailpit/`log/slog`, default fora de prd) e `ResendProvider` (só em prd).
- **Guard como decorator da interface:** `func Guarded(p EmailProvider, env Env, testDomains []string, cap int) EmailProvider` — deny-by-default no destinatário (domínio de teste ou subdomínio dele; endereço malformado também recusa), **retorna `error`** (nunca `slog.Warn`/`nil`, casa com o piso "erro nunca engolido"), **cap por execução em `atomic.Int64`** (`MAIL_MAX_PER_RUN`, default 50 quando `cap <= 0`), mensagem de erro que **ensina o caminho certo**, e `redact()` pra não vazar PII em log/erro.
- **Wire na composição** (`cmd/auth/main.go`): seleção do provider por ambiente **uma vez**, guard embrulhando os dois casos (domínio fora de prd + cap sempre); caso de uso não conhece ambiente e **não existe `force`/`skipGuard`**.
- **Testes que veem o vermelho:** `TestGuard_RecusaDominioExterno` (em hml, `@gmail.com` ⇒ `ErrExternalRecipientBlocked` e `spyProvider` com 0 chamadas) e `TestGuard_CapAbortaExecucao` (3º envio com `cap=2` ⇒ `ErrRunCapExceeded`).
- **Piso inegociável na `SKILL.md`** + linha no mapa de references apontando pro §3.1, com a normativa na `schematize-engineering` → `references/efeitos-externos.md`.
- **`assets/CLAUDE.md`: piso 17** (efeito externo nunca sai de não-prd) e menção na Definition of Done.
- **Checklist do `references/iam.md`**: item de DoD do sink/guard/cap/domínio de teste/chave sandbox provado por teste.

## [1.9.2] — 2026-08-18
Correção da contradição do muro pré-login de IAM (alinha ao `iam.md` da schematize-engineering).
### Mudado
- **/go-iam**: removido o "2º fator forte obrigatório antes do acesso pleno" e o "força 2º fator no 1º login" — o muro pré-login / deadlock de bootstrap VETADO pela norma. Agora senha+Email OTP = 2FA baseline; fator forte é nudge + step-up just-in-time.

## [1.9.1] — 2026-08-18
Q.A. repointado para a skill dedicada **schematize-qa**.
### Mudado
- **`/go-qa` virou wrapper fino** da **schematize-qa** (`/qa-plan` → `/qa-run`) no recorte Go (`go test -race`). Referências ao antigo **§22.9** (Q.A. plan-first, agora extraído para a schematize-qa) removidas de `SKILL.md`, `references/testes*.md`, `assets/CLAUDE.md` e `/go-help`.

## [1.9.0] — 2026-08-15
Correção de desenho no IAM backend — **senha + Email OTP já é 2FA baseline** (o middleware/PEP não barra mais o login) + **risk engine adaptativo robusto**.

### Mudado (correção de piso)
- **`references/iam.md` §3/§4/§7 + roadmap + checklist:** senha + Email OTP conta como **2FA baseline** desde o cadastro; o **middleware/PEP libera o acesso baseline** e exige AAL alto **só por rota sensível** (step-up just-in-time, `403 step_up_required`), **nunca barra o login** por falta de fator forte — fim do **círculo infinito**. Fator forte é **nudge + just-in-time**. Migração ativa o Email OTP always-on como 2º fator baseline (sem muro).

### Adicionado
- **Autenticação adaptativa por risco (robusta)** (`references/iam.md` §9): log de sessões/tentativas + **score** (IP/ASN, device novo, geovelocidade, velocity, honeypot); **escalonamento 2FA→3FA** sob risco (senha → email → app/chave); **negação deceptiva/tarpit** (falso negativo sob suspeita — resposta idêntica ao erro real em **tempo constante**, estado "próxima passa" curto/escopado a conta+IP+device, soma-se ao 3FA, nunca trava o legítimo); **honeypot**; notifica login suspeito + "não fui eu".

## [1.8.0] — 2026-07-11
IAM por desenho (recorte Go) — identidade + autorização robustas, auth como microserviço Go separado.

### Adicionado
- **`references/iam.md`** — piso de IAM da casa no recorte **backend/Go**: **auth é app SEPARADA** — **microserviço Go** `<projeto>_auth_go` + front próprio (`<projeto>_authfront`) em `auth.<domain>`, isolados; nunca monolith (nem `internal/auth`); apps delegam por OIDC/OAuth2.1 + PKCE e validam por **JWKS público** (assinatura só no auth). **ID interno imutável (ULID/UUIDv7) — email/telefone nunca é ID** (N emails por usuário como entidades filhas com `VerifiedAt`; SSO com recuperação local forçada; nudge de email secundário com detecção de provedor + tooltip). **≥2 fatores sempre** (AAL/NIST 800-63B): **passkey/WebAuthn no núcleo** (`go-webauthn`), TOTP (`pquerna/otp`)/push, **email OTP Resend always-on inclusive HML**, **Twilio** p/ telefone — providers como **interfaces Go plugáveis** (`EmailProvider`/`SmsProvider`/`PushProvider`); senha por padrão (**argon2id** via `x/crypto/argon2` + HIBP) mas opcional no seletor; invariante de troca "fator Y≠X no maior AAL"; **recuperação ≥ força do login**. **Multi-tenant RBAC/ABAC granular via ReBAC** (OpenFGA/SpiceDB via client): deny-default, PDP=Check API / **PEP=middleware Go**, enforcement server-side, token fino, decisão auditada, escrita de tupla via outbox. **Multi-dispositivo** + view de remover (session store Postgres+Redis, `refresh_family_id`/`device_id`/`jti`); **sessão 7d/90d** (fim do "15 min e é chutado") com refresh rotativo silencioso; **logout irreversível** (revoga refresh+família, apaga sessão server-side, `jti` na denylist consultada em toda request). **Migração de auth legado = prioridade 0** (strangler-fig, re-hash preguiçoso → argon2id, re-deriva authz). Rotina agressiva de testes cross-tenant/priv-esc (schematize-pentest).
- **Comando `/go-iam`** (plan-first): força/audita/scaffolda o IAM num projeto (bootstrap) ou porta um auth legado (migrate).
- **Piso 16** no `CLAUDE.md`; bullet + linha na tabela de references do `SKILL.md`; anti-padrões **43–46** (auth monolith; email como ID / 1 fator; authz hand-rolled/no cliente; logout que só apaga cookie); `/go-load` carrega `iam.md`; `/go-help` lista `/go-iam`.

## [1.7.0] — 2026-07-11
Limite de arquivo em camadas — teto de 750 (≤500 úteis + ~250 comentário) + flag em >300 úteis.

### Alterado
- **`references/padroes-codigo.md` §1/§2:** o limite rígido de **300 linhas/arquivo** vira regra **em camadas**. **Teto DURO: 750 linhas** (das quais **~250 reservadas a comentário/doc** e **até ~500 de código útil**) — acima bloqueia. **FLAG (não bloqueia, mas SEMPRE sinaliza) em > 300 linhas de código útil:** indício de que a função está **muito extensa** / **precisa de mais abstração** — registra como dívida e **revê quando as prioridades forem resolvidas**. **Observabilidade tem folga natural (~400 úteis).** Função com >300 úteis dispara o mesmo flag; "uma função por arquivo" mantida.
- **`scripts/check-diff.sh`:** o gate de tamanho passa a contar **código útil** (exclui comentário/branco): `total > 750` **bloqueia**, `útil > 500` **bloqueia**, `útil > 300` (ou `> 400` em arquivo de observabilidade) **flagueia** (`warn`, não trava).
- Propagado no piso do `CLAUDE.md`, `SKILL.md`, `references/entrega.md` (DoD), `references/arquitetura.md` (§6) e comandos `/go-load` `/go-help` `/go-review`.

## [1.6.0] — 2026-07-06
Deploy destrutivo por seed + isolamento por usuário (ops).

### Adicionado
- references/ops.md §2: layout /<app>/ + repos clonados dentro; /<app>/.env como seeder global (fonte única); redeploy destrutivo na aplicação (apaga e recria clone zerado do seed), preservando DADOS (migration reversível; ops reset de dados só dev/hml).
- references/ops.md §3: isolamento por usuário — user Linux + systemd unit hardened por serviço (blast radius mínimo); tudo automatizado pelo ops.
- Piso de seed/isolamento no CLAUDE.md; anti-padrões (patch in-place/redeploy fora do seed; config/repos fora de /<app>/; apagar dados no destrutivo; serviços sem isolamento de user); /go-ops audita layout/seed/isolamento.

## [1.5.0] — 2026-07-05
Control plane <projeto>_ops: fluxo de ambientes, ops interface única, instalação paralela, independência invariante.

### Adicionado
- references/ops.md: fluxo dev→local→github→hml→prd (nada direto no servidor; servidor imutável por edição manual), ops como interface única (100%, autônomo — usuário provisiona do zero sem IA), instalação paralela=nproc, independência invariante (falha no paralelo = serviços não independentes → prioridade máxima; nunca serializar pra mascarar).
- Comando /go-ops; pisos de ambientes/ops no CLAUDE.md; anti-padrões (editar no servidor, pular pra hml/prd, operar fora do ops, instalar serial, serializar pra mascarar); operacao.md §21 estendido; /go-load carrega ops.md.

## [1.4.0] — 2026-07-05
Todo MD gerado no archive, root limpo.

### Corrigido
- MAPA/índice saíam no root → agora `<projeto>_archive/index/` (padroes-codigo §4, MAPA.md, /go-index, build-index.mjs, CLAUDE.md, SKILL.md).

### Adicionado
- §28.0 (operacao.md): layout canônico do archive — todo MD gerado (MAPA, índices, planos, relatórios, handoffs) em `<projeto>_archive/<área>/`, NUNCA no root.

## [1.0.0] — 2026-06-20
Primeira release sob o nome **schematize-go** — padrões normativos de engenharia da casa.

### Adicionado
- Conhecimento normativo completo fatiado em `references/` (arquitetura, segurança,
  dados/eventos, testes/pentest, observabilidade, operação, anti-padrões, contexto).
- Comandos: `/go-help`, `/go-cc`, `/go-handoff`, `/go-qa`, `/go-review`, `/go-index`.
- Scripts: `lib.sh`, `test-skeleton.sh`, `smoke-selfcheck.sh`, `simulated/run.py`,
  `build-index.mjs`, `check-diff.sh`, `archive-secret-scan.sh`, hooks de contexto.
- Assets: `CLAUDE.md`, templates (ADR/TASK/CHAT/PR/RUNBOOK/INDEX_*), `settings.claude.example.json`,
  CI (`ci/`), guard-tests de import (`lint/`), pre-commit (`hooks/`).
- Site `skills.schematize.me/go` (multi-idioma, AI-friendly) + instalador.

### Normativo coberto
- Backend só Go/Rust; Node backend proibido (migração por funcionalidade, §3.1);
  PHP proibido (§3.2); frontend Node 100% permitido (§3).
- Arquivos ≤300 linhas + micro-funções; toda função documentada (§6).
- Índice de funcionalidades como fonte da verdade (§39).
- Q.A. plan-first (§22.9); handoff de contexto (§34.1); archive obrigatório (§28).
- Anti-padrões vetados (§37); testes/pentest com gate de "verde de verdade" (§22).
