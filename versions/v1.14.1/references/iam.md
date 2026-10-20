# IAM — Identidade e Autorização da casa (piso inegociável) — recorte backend/Go

> **PONTEIRO, não cópia.** A normativa agnóstica de IAM é da base:
> **`schematize-engineering`** → `references/iam.md`. **Onde este arquivo divergir da
> base, a BASE MANDA.**
>
> **Promovidas para a base em 2026-08-21** (viviam em 5–7 cópias aqui e em nenhum lugar lá): §5.1
> **outbox transacional** na escrita de tupla ReBAC · **PDP fail-closed** · **denylist de `jti` como
> consulta obrigatória**; §6 **refresh opaco CSPRNG hasheado**; §9 **comparação em tempo constante**
> na negação deceptiva; **CSPRNG obrigatório** em toda aleatoriedade de segurança; *"framework de
> auth pronto ≠ IAM da casa"*; §2.1 **parâmetros mínimos de argon2id**. Aqui elas aparecem só no que
> muda de linguagem (a biblioteca, o tipo, o runtime).

> **Dona do tema: `schematize-iam`.** Topologia do broker, fatores, sessão, ReBAC, risco e recuperação vivem em
> `schematize-iam → references/` (`topologia.md`, `fatores.md`, `sessao.md`, `authz-rebac.md`, `recuperacao-risco.md`);
> a normativa agnóstica de base é `schematize-engineering → references/iam.md`. Este arquivo guarda só o recorte de linguagem.

## 1. Topologia — auth é uma APLICAÇÃO SEPARADA (microserviço Go)

- **Microserviço de auth em Go** (`<projeto>_auth_go`) + **front de auth** próprio
  (`<projeto>_authfront`), com **repo, deploy, user Linux e systemd/container isolados**
  por conta própria (casa com o isolamento por app do `schematize-engineering` -> `ops.md` §3). Comprometer o app
  principal **não** compromete o IdP. O binário do auth é o **único** que carrega a chave
  privada de assinatura e os segredos de provedor (Resend/Twilio/OAuth).

- **O app principal (e todo cliente) delega ao auth por OIDC/OAuth2.1 + PKCE:** redireciona
  pra `auth.<domain>`, recebe tokens de volta. O serviço Go de auth é o **IdP da casa**
  (padrão self-hosted, consumido por N apps) — expõe os endpoints padrão
  (`/authorize`, `/token`, `/introspect`, `/revoke`, `/.well-known/openid-configuration`,
  `/.well-known/jwks.json`).

- **Segredos e chave de assinatura de token vivem SÓ no serviço de auth Go**; consumidores
  (middleware Go dos outros serviços) validam por **JWKS público** cacheado — nunca
  guardam a chave privada. A assinatura JWT (Ed25519/EdDSA ou RS256) só acontece dentro
  de `<projeto>_auth_go`; a rotação de chave é publicada via `kid` no JWKS.

## 2. Modelo de identidade

- **ID interno imutável e opaco** (ULID/UUIDv7) é o `sub`. **Email e telefone NUNCA são
  ID** — são *identificadores* ligados ao usuário, cada um com estado de verificação. Em
  Go, o agregado `User` tem `ID` opaco; `Email`/`Phone` são entidades filhas com
  `VerifiedAt *time.Time`, nunca a PK.

## 3. Fatores e níveis de garantia (AAL — NIST 800-63B)

- **Email OTP (Resend) ligado por padrão, inclusive em HML** — só o operador desliga.

- **Provedores plugáveis como interfaces Go:** o core depende de interfaces, não de SDK:

  ```go
  type EmailProvider interface { SendOTP(ctx context.Context, to string, code string) error }
  type SmsProvider   interface { SendOTP(ctx context.Context, to string, code string) error }
  type PushProvider  interface { RequestApproval(ctx context.Context, deviceToken string, challenge Challenge) (Approval, error) }
  ```

  `EmailProvider` (Resend default), `SmsProvider` (Twilio default), `PushProvider` são
  **trocáveis por config/wiring**, sem tocar no core (adaptadores na borda, DDD).

- **WebAuthn/passkey** por lib madura (ex.: `go-webauthn/webauthn`); **TOTP** por
  `pquerna/otp`. Assinatura/JWT por `go-jose` ou equivalente auditado.

- **Senha por padrão, opcional por escolha:** o usuário **cria senha no cadastro** (padrão
  cultural; **argon2id** via `golang.org/x/crypto/argon2` (`IDKey`) + verificação contra
  base de vazadas/HIBP k-anonymity), mas o **seletor de modos de autenticação permite
  marcá-la como opcional** e viver de passkey/OTP/app.
  > **Parâmetros mínimos (`m` ≥ 19 MiB, `t` ≥ 2, `p` = 1, salt ≥ 16 B CSPRNG, string codificada
  > guardada inteira, re-hash preguiçoso):** na base — `schematize-engineering`, seu
  > `references/iam.md`, seção **2.1 ("Hash de senha — argon2id com parâmetros MÍNIMOS")**.
  > **Nenhuma das 8 skills fixava os números** até 2026-08-21 — e argon2id mal parametrizado é
  > mais fraco que bcrypt bem configurado. Calibre para ~0,5–1 s no hardware do auth e registre
  > o valor medido no ADR do serviço; o default da lib normalmente é o mais fraco. O `argon2.IDKey` recebe `m`/`t`/`p` explícitos — não há default seguro implícito.

- **2FA por desenho desde o cadastro — senha + Email OTP JÁ é 2FA (fraco, porém válido):**
  a conta **nasce com dois fatores obrigatórios** (senha + código no email verificado,
  always-on) e **já é segura para o baseline**. **VETADO** tratar senha+OTP como "sem 2FA" e
  **barrar o login** até enrolar um fator forte — é o **círculo infinito**. Em Go: o middleware
  de sessão **libera o acesso baseline** com a sessão de AAL médio (senha+OTP); **não** barra
  todas as rotas exigindo AAL alto.

- **Fator forte é INCENTIVADO + just-in-time, nunca muro pré-login:** app OTP / passkey / chave
  são **nudge** e **exigidos só na operação sensível** (o PEP checa o AAL mínimo **por rota
  sensível** e dispara **step-up** ali) e **escalados sob risco** (§9). Enrolar um fator forte
  usa o Email OTP como verificação (Y≠X, §4): sem deadlock. A ausência de fator forte **degrada
  o que é sensível** (`403 step_up_required`), não **bloqueia o baseline**.

## 3.1 Efeito externo fora de prd — o guard mora DENTRO do provider (recorte Go)

O Email OTP é always-on (§3): é **daqui** que sai e-mail em todo ambiente. Normativa completa
(as 4 camadas, o DNS, a exceção com ADR) na **schematize-engineering**,
`references/efeitos-externos.md` — este é o **recorte Go**. Regra: fora de `prd`, **nenhum
e-mail/SMS/push/webhook chega em ninguém**, por construção. Um laço de teste que cria 5.000
contas dispara 5.000 OTPs; endereço sintético vira **hard bounce**/spam trap, e bounce
acima do limiar **queima o IP e o domínio** — derrubando o transacional de prd, **inclusive o
OTP de login deste próprio IAM**. Semanas de warm-up, utilidade zero, sem undo.

**Piso Go, em quatro linhas:**

1. **`EmailProvider` já é interface** (§3) — então o guard é um **decorator** da interface, e o
   provider real é **SinkProvider** (Mailpit/`log/slog`) fora de prd.

2. O guard **não mora no chamador** (caso de uso esquece; teste chama o SDK direto): ele
   embrulha o provider na **composição** (`cmd/<svc>/main.go`), uma vez.

3. Ele **retorna `error`** — nunca `nil` silencioso, nunca só um `slog.Warn`. Casa com o piso
   "erro nunca engolido": quem chamou trata o `error` ou o propaga.

4. **Cap por execução** com contador atômico (`MAIL_MAX_PER_RUN`, default 50) — os 5.000 só
   existiram porque **nada estava contando**.

**Endereço sintético:** `<papel>+<run-id>-<n>@test.<domain>` (ou TLD reservado `.test`/
`.invalid`/`.example`). **VETADO** em fixture/seed/persona/demo/carga: `@gmail.com`,
`@hotmail.com`, domínio de cliente/terceiro, e-mail de pessoa real (**inclusive o seu**) e o
domínio de **produção**. Chave de não-prd é **sandbox**, nunca a de prd.

### A porta e os erros — `internal/platform/mail`

```go
// Package mail é a borda de saída de e-mail (adaptador DDD). O core depende da
// interface; quem sabe falar com Resend/Mailpit é este pacote.
package mail

// Message é o que o domínio pede pra enviar — sem SDK vazando pra dentro.
type Message struct {
	To      string
	Subject string
	Body    string
}

// EmailProvider é a porta. Toda impl (real, sink, guard) satisfaz esta interface,
// então o guard pode embrulhar qualquer uma delas sem o chamador saber.
type EmailProvider interface {
	Send(ctx context.Context, msg Message) error
}

// Erros sentinela: o chamador (e o teste) distingue por errors.Is, não por string.
var (
	// ErrExternalRecipientBlocked = destinatário fora do domínio de teste com env != prd.
	ErrExternalRecipientBlocked = errors.New("mail: destinatário externo bloqueado fora de prd")
	// ErrRunCapExceeded = teto de envios desta execução estourado (circuit breaker).
	ErrRunCapExceeded = errors.New("mail: cap de envio por execução estourado")
)

// Env é o ambiente resolvido. ParseEnv é FAIL-CLOSED: valor ausente, vazio ou
// desconhecido cai em EnvDev (o modo seguro) — nunca em prd por acidente.
type Env string

const (
	EnvDev Env = "dev"
	EnvHml Env = "hml"
	EnvPrd Env = "prd"
)

func ParseEnv(raw string) Env {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "prd", "prod", "production":
		return EnvPrd
	case "hml", "staging", "stg":
		return EnvHml
	default:
		return EnvDev // fail-closed: sem declaração explícita, assume não-produção
	}
}
```

### O sink (default fora de prd) e o provider real

```go
// SinkProvider é o default fora de prd: a mensagem NÃO sai da máquina. Em dev/hml
// aponte para o Mailpit (SMTP :1025, UI/API HTTP :8025) quando o teste precisar LER
// a caixa; o log estruturado basta quando só precisa provar que houve envio.
type SinkProvider struct{ log *slog.Logger }

func NewSinkProvider(log *slog.Logger) *SinkProvider { return &SinkProvider{log: log} }

// Send apenas registra. O endereço vai REDIGIDO — PII não entra em log (LGPD).
func (s *SinkProvider) Send(ctx context.Context, msg Message) error {
	s.log.InfoContext(ctx, "mail.sink",
		slog.String("provider", "sink"),
		slog.String("to", redact(msg.To)),
		slog.String("subject", msg.Subject),
	)
	return nil
}

// ResendProvider é o provider real. Só é construído na composição quando env == prd
// (ou sob a exceção com ADR), e a chave é a de prd — em não-prd, chave SANDBOX.
type ResendProvider struct {
	http   *http.Client
	apiKey string
	from   string
}

func NewResendProvider(apiKey, from string) *ResendProvider {
	return &ResendProvider{
		http:   &http.Client{Timeout: 10 * time.Second},
		apiKey: apiKey,
		from:   from,
	}
}

func (p *ResendProvider) Send(ctx context.Context, msg Message) error {
	payload, err := json.Marshal(map[string]any{
		"from": p.from, "to": []string{msg.To}, "subject": msg.Subject, "html": msg.Body,
	})
	if err != nil {
		return fmt.Errorf("mail: serializar payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.resend.com/emails", bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("mail: montar request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+p.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := p.http.Do(req)
	if err != nil {
		return fmt.Errorf("mail: chamar resend: %w", err)
	}
	// DRENAR antes de fechar, sempre — inclusive no caminho de erro. Fechar um body não lido
	// faz o transporte descartar a conexão em vez de devolvê-la ao pool keep-alive; em volume
	// isso vira socket churn (e, com o pool sob pressão, esgotamento de porta efêmera). O
	// limite existe para o corpo de erro gigante não virar o DoS que se está tentando evitar.
	defer func() {
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
		_ = resp.Body.Close()
	}()

	if resp.StatusCode >= http.StatusMultipleChoices {
		return fmt.Errorf("mail: resend respondeu %s", resp.Status)
	}
	return nil
}
```

### O guard — decorator, deny-by-default, com cap atômico

```go
// guarded embrulha um EmailProvider e é o ÚNICO ponto que decide se a mensagem
// pode sair. Não é exportado de propósito: constrói-se por Guarded, então não dá
// pra montar um provider "sem guard" por engano.
type guarded struct {
	next        EmailProvider
	env         Env
	testDomains []string
	maxPerRun   int64
	sent        atomic.Int64 // contador por execução do processo
}

// Guarded devolve o provider embrulhado. Aplique-o em TODOS os ambientes: em prd o
// guard de domínio é no-op, mas o CAP continua valendo (laço maluco também existe em prd).
// maxPerRun <= 0 cai no default 50 — fail-closed: "não configurei" não vira "ilimitado".
//
// O parâmetro NÃO se chama `cap`: `cap` é builtin do Go, e sombreá-lo dentro desta função
// tornaria `cap(slice)` inacessível aqui — o compilador não reclama, e o próximo a mexer
// descobre no lugar errado. Vale o mesmo para `len`, `new`, `max`, `min` e `copy`.
func Guarded(p EmailProvider, env Env, testDomains []string, maxPerRun int) EmailProvider {
	if maxPerRun <= 0 {
		maxPerRun = 50
	}
	normalized := make([]string, 0, len(testDomains))
	for _, d := range testDomains {
		normalized = append(normalized, strings.ToLower(strings.TrimSpace(d)))
	}
	return &guarded{next: p, env: env, testDomains: normalized, maxPerRun: int64(maxPerRun)}
}

// Send aplica, nessa ordem: deny-by-default de destinatário, cap por execução e só
// então delega. Qualquer recusa devolve error — nunca warning, nunca no-op silencioso.
func (g *guarded) Send(ctx context.Context, msg Message) error {
	if err := g.assertDeliverable(msg.To); err != nil {
		return err
	}
	if n := g.sent.Add(1); n > g.maxPerRun {
		return fmt.Errorf("%w: tentativa %d, teto %d (MAIL_MAX_PER_RUN). Nada foi enviado",
			ErrRunCapExceeded, n, g.maxPerRun)
	}
	return g.next.Send(ctx, msg)
}

// assertDeliverable é o guard propriamente dito: em prd entrega de verdade; fora de
// prd só passa endereço no domínio de teste (rota nula). Endereço malformado também
// é recusa — deny-by-default. A mensagem de erro ENSINA o caminho certo
		// (§37, "Culpar o usuário / exigir que ele saiba de internals").
func (g *guarded) assertDeliverable(to string) error {
	if g.env == EnvPrd {
		return nil
	}
	at := strings.LastIndex(to, "@")
	if at < 0 {
		return fmt.Errorf("%w: %q não é um endereço válido", ErrExternalRecipientBlocked, redact(to))
	}
	domain := strings.ToLower(to[at+1:])
	for _, t := range g.testDomains {
		// domínio exato ou subdomínio dele (test.<domain> cobre a.test.<domain>).
		if domain == t || strings.HasSuffix(domain, "."+t) {
			return nil
		}
	}
	return fmt.Errorf("%w: %s em env=%s. Use <papel>+<run-id>-<n>@%s (null MX) ou registre o ADR de exceção (as 5 condições). Nada foi enviado",
		ErrExternalRecipientBlocked, redact(to), g.env, hintDomain(g.testDomains))
}

// redact esconde a parte local do endereço: PII nunca vai crua pra log nem pra erro.
func redact(addr string) string {
	at := strings.LastIndex(addr, "@")
	if at <= 0 {
		return "***"
	}
	return "***@" + addr[at+1:]
}

// hintDomain devolve o domínio de teste a sugerir na mensagem de erro.
func hintDomain(domains []string) string {
	if len(domains) == 0 {
		return "test.<domain>"
	}
	return domains[0]
}
```

### Wire na composição, nunca no chamador

```go
// cmd/auth/main.go — a escolha do provider acontece UMA vez, aqui.
func newEmailProvider(cfg Config, log *slog.Logger) mail.EmailProvider {
	var base mail.EmailProvider
	if cfg.Env == mail.EnvPrd {
		base = mail.NewResendProvider(cfg.ResendAPIKey, cfg.MailFrom) // só em prd
	} else {
		base = mail.NewSinkProvider(log) // DEFAULT fora de prd
	}
	// O guard embrulha os dois casos: domínio (fora de prd) + cap (sempre).
	return mail.Guarded(base, cfg.Env, cfg.TestMailDomains, cfg.MailMaxPerRun)
}
```

O caso de uso do OTP recebe `mail.EmailProvider` por injeção e **não conhece ambiente**: ele
só chama `Send` e **trata o `error`**. Não existe parâmetro `force`/`skipGuard` — bypass por
argumento é a porta que sempre acaba aberta em produção.

### O teste que vê o vermelho (`internal/platform/mail/guard_test.go`)

```go
// spyProvider conta chamadas: prova que o provider real NÃO foi acionado.
type spyProvider struct{ calls atomic.Int64 }

func (s *spyProvider) Send(context.Context, mail.Message) error {
	s.calls.Add(1)
	return nil
}

// TestGuard_RecusaDominioExterno prova o piso: em hml, e-mail pra caixa real é ERRO
// e nada sai. Se este teste ficar verde por acidente (guard removido), o próximo
// laço de carga manda 5.000 e-mails de verdade.
func TestGuard_RecusaDominioExterno(t *testing.T) {
	t.Parallel()

	spy := &spyProvider{}
	provider := mail.Guarded(spy, mail.EnvHml, []string{"test.exemplo.com.br"}, 50)

	err := provider.Send(context.Background(), mail.Message{
		To: "alguem@gmail.com", Subject: "otp", Body: "123456",
	})

	if !errors.Is(err, mail.ErrExternalRecipientBlocked) {
		t.Fatalf("esperava ErrExternalRecipientBlocked; veio %v", err)
	}
	if got := spy.calls.Load(); got != 0 {
		t.Fatalf("provider real chamado %d vez(es); deveria ser 0", got)
	}
}

// TestGuard_CapAbortaExecucao prova o circuit breaker: o 3º envio com cap=2 falha.
func TestGuard_CapAbortaExecucao(t *testing.T) {
	t.Parallel()

	spy := &spyProvider{}
	provider := mail.Guarded(spy, mail.EnvHml, []string{"test.exemplo.com.br"}, 2)
	msg := mail.Message{To: "qa+run42-1@test.exemplo.com.br", Subject: "otp", Body: "123456"}

	for i := 1; i <= 2; i++ {
		if err := provider.Send(context.Background(), msg); err != nil {
			t.Fatalf("envio %d dentro do cap falhou: %v", i, err)
		}
	}
	if err := provider.Send(context.Background(), msg); !errors.Is(err, mail.ErrRunCapExceeded) {
		t.Fatalf("esperava ErrRunCapExceeded no 3º envio; veio %v", err)
	}
	if got := spy.calls.Load(); got != 2 {
		t.Fatalf("provider real chamado %d vez(es); deveria ser 2", got)
	}
}
```

O mesmo desenho vale para `SmsProvider` (Twilio), `PushProvider` e qualquer webhook de
terceiro: **interface + sink default + guard decorator + cap**. Entregar de verdade fora de
prd exige **as cinco** condições da normativa (ADR aceito, allowlist ≤5 endereços da casa,
cap, janela com expiração, subdomínio de envio separado) — faltou uma, não roda.

## 4. Fluxos

**Onboarding:** email verificado -> senha (ou passkey/app) -> acesso baseline pleno com 2FA (senha + Email OTP). Fator forte
é nudge depois de entrar e step-up just-in-time na ação sensível ou sob risco (§9); **nunca** muro pré-login.
Fluxos completos e invariante de troca de fator: `schematize-iam → references/fatores.md`.

## 5. Multi-tenant + RBAC/ABAC — motor ReBAC (estilo Zanzibar)

- **PDP/PEP separados:** PDP = **Check API** do motor; **PEP = middleware Go** em cada
  serviço (`func RequirePermission(perm string) gin.HandlerFunc` / `func(next http.Handler)`),
  que extrai `sub`+tenant do token e chama `Check(ctx, obj, rel, subject)`.
  **Deny-by-default** (erro/timeout do PDP = nega), enforcement **server-side**, **todo
  endpoint mapeia 1 permissão**.

- **Token fino:** o JWT carrega `sub`/tenant/sessão/AAL — **sem** a lista de permissões
  (evita authz stale em token longo); a decisão é consultada no PDP e cacheada com TTL
  curto (in-memory/Redis) invalidado por evento de mudança de papel.

## 6. Sessão, multi-dispositivo e logout

- **Refresh rotativo com detecção de reuso** (reusou -> revoga a família inteira); refresh opaco, aleatório de CSPRNG (`crypto/rand`),
  hasheado no store; família e `jti` rastreados server-side.
- **Logout irreversível:** revoga refresh e família, apaga a sessão server-side, `jti` na denylist até expirar, desassocia o push token.
  Em Go: o handler de logout do auth Go; o middleware de validação consulta a denylist de `jti` (cache curto).
- Modelo completo, cookies e gate: `schematize-iam → references/sessao.md`.

## 7. Migração de auth legado — PRIORIDADE 0

Auth legado existente: portar para este IAM é prioridade máxima (strangler-fig, dual-run). Em Go: **re-hash preguiçoso**
no login (verifica no algoritmo antigo, regrava em argon2id com `golang.org/x/crypto/argon2` (`IDKey`)); o auth migrado nasce como microserviço Go separado (§1).
Passos de migração (dedupe de emails, IDs ULID/UUIDv7, Email OTP baseline, revogar sessões legadas, re-derivar authz pelas tuplas):
`schematize-iam → references/recuperacao-risco.md` §6. Legado Node/PHP segue a regra de migração da casa
(`schematize-engineering → references/linguagens.md`).

## 8. Rotina agressiva de testes (detalhe na schematize-pentest)

- **Abuso de fluxo:** bypass de 2FA, reset pulando 2FA, brute-force/rate-limit de OTP,
  replay de token, reuso de refresh, JWT `alg=none`/kid trocado, session fixation,
  adulteração de asserção SSO, IDOR na gestão de identificadores, bypass de step-up,
  mass-assignment de papel, **logout que não invalidou de verdade** (sessão recuperável).

## 9. Autenticação adaptativa por risco (robusta) + transversais

A resposta ao login varia com o risco calculado. Piso: log de sessões/tentativas com score (IP/ASN, device, geo, velocity, honeypot);
escalonamento 2FA->3FA sob risco (senha -> email -> app/chave); negação deceptiva com resposta e tempo idênticos ao erro real
(comparação em tempo constante, estado curto e escopado, nunca lockout do legítimo); honeypot; anti-automação (rate-limit, backoff,
lockout progressivo conta+IP); notificação ao usuário com "não fui eu". Detalhe e parâmetros:
`schematize-iam → references/recuperacao-risco.md` §2-§4.

### Transversais (sempre)

- **Audit log imutável** de toda decisão authn/authz e mudança de credencial — alimenta a
  forense e os testes (liga com a observabilidade LGTM+ da casa; spans OpenTelemetry no
  fluxo de login/authz com `trace_id`).

## Roadmap de fases

- **F2** Multi-tenant + **ReBAC** (membership, papéis granulares, PDP/PEP em middleware Go,
  deny-default, token fino, audit).

## Checklist (entra na Definition of Done quando o projeto tem auth)

- [ ] Auth é **app separada** — microserviço Go `<projeto>_auth_go` + front próprios em `auth.<domain>`, isolados — não monolith.

- [ ] **ID interno imutável** (ULID/UUIDv7); email/telefone não são ID; múltiplos emails suportados.

- [ ] **2FA baseline por desenho** (senha + Email OTP = 2FA desde o cadastro); fator forte é **nudge + just-in-time (step-up)**, **NUNCA muro pré-login** (o middleware libera o baseline, exige AAL alto só por rota sensível); passkey no núcleo; email OTP always-on; Twilio; providers como interfaces Go.

- [ ] **Risk engine adaptativo:** log de sessões/tentativas + score (IP/device/geo/velocity/honeypot); **2FA→3FA** sob risco; **negação deceptiva/tarpit** (falso negativo, resposta idêntica ao erro real em tempo constante, "próxima passa" curta/escopada); notifica login suspeito.

- [ ] Invariante de troca de fator (Y≠X, maior AAL); recuperação ≥ login; SSO com recuperação local; senha em **argon2id**+HIBP.

- [ ] **Multi-tenant + RBAC/ABAC** (ReBAC OpenFGA/SpiceDB), deny-default, PDP=Check API / PEP=middleware Go, enforcement server-side, token fino.

- [ ] Multi-dispositivo + view de remover; **sessão 7d/90d**; **logout irreversível** (revoga refresh+família, `jti` na denylist, não só cookie).

- [ ] JWKS público (assinatura só no auth); audit log de authn/authz; risk engine/rate-limit; migração de legado tratada como prioridade 0.

- [ ] **Efeito externo fora de prd (§3.1):** `EmailProvider`/`SmsProvider` com **sink default** fora de `prd`, **guard decorator DENTRO do provider** (`mail.Guarded`) devolvendo `error`, **cap por execução** com contador atômico, endereço sintético só em `test.<domain>` (null MX) e chave **sandbox** — provado por `TestGuard_RecusaDominioExterno` (espera a recusa) e `TestGuard_CapAbortaExecucao`.
