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

4. **Cap por execução SÓ fora de prd** (contador atômico, `MAIL_MAX_PER_RUN`, default 50) — os
   5.000 só existiram porque **nada estava contando**. **Em prd NÃO há teto por processo**: o IdP
   é serviço de longa duração e um cap de vida do processo derrubaria o **OTP de login** depois do
   50º envio. Em prd o guard é **fail-closed por destinatário/domínio** (endereço único e bem
   formado) e a proteção é **rate-limit por destinatário, idempotência e circuit breaker**; o
   volume agregado vira alerta.

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
	// IdempotencyKey identifica o PEDIDO (ex.: id do desafio OTP). Em prd, a reentrega com a
	// mesma chave não envia de novo. Vazio ⇒ sem deduplicação.
	IdempotencyKey string
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
	// ErrRunCapExceeded = teto de envios desta execução estourado (circuit breaker). SÓ fora de prd.
	ErrRunCapExceeded = errors.New("mail: cap de envio por execução estourado")
	// ErrInvalidRecipient = destinatário não é UM endereço simples (lista, CR/LF, "<>", malformado).
	ErrInvalidRecipient = errors.New("mail: destinatário inválido")
	// ErrRecipientRateLimited = rate-limit por destinatário estourado (prd).
	ErrRecipientRateLimited = errors.New("mail: rate-limit por destinatário")
	// ErrCircuitOpen = circuit breaker do provider aberto (prd): falha rápida, sem martelar.
	ErrCircuitOpen = errors.New("mail: circuit breaker aberto")
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

### O guard — decorator, deny-by-default; cap SÓ fora de prd, rate-limit/breaker em prd

O guard tem **dois regimes**, escolhidos por `Env` (fail-closed: ambiente desconhecido ⇒ não-prd):

| | fora de prd (dev/hml) | prd |
|---|---|---|
| Destinatário | **só** o domínio de teste (rota nula); o resto é `error` | **fail-closed por destinatário/domínio**: endereço único e bem formado, senão `error` |
| Volume | **cap por execução** (`MaxPerRun`, default 50) — circuit breaker de laço de teste | **sem teto fixo por processo**: rate-limit por destinatário (janela deslizante), idempotência por chave e circuit breaker do provider |
| Por quê | os 5.000 e-mails só existiram porque nada contava | o IdP é serviço de longa duração: um teto de vida do processo derrubaria o **OTP de login** depois do N-ésimo envio (autoataque de disponibilidade) |

Em prd o volume agregado é **alerta** (`mail_sent_total`, `mail_blocked_total` — normativa
`schematize-engineering` → `references/efeitos-externos.md`), não teto duro.

```go
// PrdLimits é a proteção de PRD. NÃO existe teto de envios por processo em prd.
// Zero value ⇒ defaults (fail-closed: "não configurei" não vira "ilimitado").
type PrdLimits struct {
	PerRecipient    int           // máx. envios ao MESMO destinatário por janela (default 5)
	Window          time.Duration // janela deslizante (default 10m)
	BreakerFailures int           // falhas seguidas do provider que abrem o breaker (default 5)
	BreakerCooldown time.Duration // tempo com o breaker aberto (default 30s)
}

// GuardConfig: cada ambiente usa só o seu pedaço.
type GuardConfig struct {
	Env         Env
	TestDomains []string         // fora de prd: únicos domínios entregáveis
	MaxPerRun   int              // SÓ fora de prd (<=0 ⇒ 50); IGNORADO em prd
	Prd         PrdLimits        // SÓ em prd
	Now         func() time.Time // nil ⇒ time.Now (o teste injeta relógio)
}

// guarded embrulha um EmailProvider e é o ÚNICO ponto que decide se a mensagem
// pode sair. Não é exportado de propósito: constrói-se por Guarded, então não dá
// pra montar um provider "sem guard" por engano.
type guarded struct {
	next EmailProvider
	cfg  GuardConfig
	sent atomic.Int64 // contador da execução — SÓ fora de prd

	mu        sync.Mutex             // protege o estado de prd abaixo
	hits      map[string][]time.Time // destinatário -> instantes de envio na janela
	seen      map[string]time.Time   // chave de idempotência -> instante
	fails     int                    // falhas seguidas do provider
	openUntil time.Time              // breaker aberto até
}

// Guarded devolve o provider embrulhado. Aplique-o em TODOS os ambientes (a validação do
// destinatário vale em todos); o que muda por ambiente está na tabela acima.
//
// O campo NÃO se chama `cap`: `cap` é builtin do Go, e sombreá-lo tornaria `cap(slice)`
// inacessível — o compilador não reclama, e o próximo a mexer descobre no lugar errado.
// Vale o mesmo para `len`, `new`, `max`, `min` e `copy`.
func Guarded(p EmailProvider, cfg GuardConfig) EmailProvider {
	if cfg.MaxPerRun <= 0 {
		cfg.MaxPerRun = 50
	}
	if cfg.Prd.PerRecipient <= 0 {
		cfg.Prd.PerRecipient = 5
	}
	if cfg.Prd.Window <= 0 {
		cfg.Prd.Window = 10 * time.Minute
	}
	if cfg.Prd.BreakerFailures <= 0 {
		cfg.Prd.BreakerFailures = 5
	}
	if cfg.Prd.BreakerCooldown <= 0 {
		cfg.Prd.BreakerCooldown = 30 * time.Second
	}
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	normalized := make([]string, 0, len(cfg.TestDomains))
	for _, d := range cfg.TestDomains {
		normalized = append(normalized, strings.ToLower(strings.TrimSpace(d)))
	}
	cfg.TestDomains = normalized
	return &guarded{
		next: p, cfg: cfg,
		hits: map[string][]time.Time{}, seen: map[string]time.Time{},
	}
}

// Send valida o destinatário (todos os ambientes) e aplica o regime do ambiente.
// Qualquer recusa devolve error — nunca warning, nunca no-op silencioso.
func (g *guarded) Send(ctx context.Context, msg Message) error {
	addr, domain, err := parseRecipient(msg.To)
	if err != nil {
		return err
	}
	if g.cfg.Env == EnvPrd {
		return g.sendPrd(ctx, msg, addr)
	}
	if err := g.assertTestDomain(addr, domain); err != nil {
		return err
	}
	if n := g.sent.Add(1); n > int64(g.cfg.MaxPerRun) {
		return fmt.Errorf("%w: tentativa %d, teto %d (MAIL_MAX_PER_RUN). Nada foi enviado",
			ErrRunCapExceeded, n, g.cfg.MaxPerRun)
	}
	return g.next.Send(ctx, msg)
}

// sendPrd: rate-limit por destinatário, idempotência e circuit breaker. O que é bloqueado
// aqui volta como error para o chamador enfileirar/tentar depois (outbox) — nunca é perdido
// em silêncio, e o OTP legítimo de um usuário nunca esbarra num teto global de processo.
func (g *guarded) sendPrd(ctx context.Context, msg Message, addr string) error {
	now := g.cfg.Now()
	win := g.cfg.Prd.Window

	g.mu.Lock()
	if now.Before(g.openUntil) {
		g.mu.Unlock()
		return fmt.Errorf("%w: provider instável, tente após %s. Nada foi enviado",
			ErrCircuitOpen, g.openUntil.Format(time.RFC3339))
	}
	if k := msg.IdempotencyKey; k != "" {
		if t, ok := g.seen[k]; ok && now.Sub(t) < win {
			g.mu.Unlock()
			return nil // reentrega do mesmo pedido: já enviado/reservado, não envia de novo
		}
	}
	hits := pruneWindow(g.hits[addr], now, win)
	if len(hits) >= g.cfg.Prd.PerRecipient {
		g.hits[addr] = hits
		g.mu.Unlock()
		return fmt.Errorf("%w: %d envios em %s para %s. Nada foi enviado",
			ErrRecipientRateLimited, len(hits), win, redact(addr))
	}
	g.hits[addr] = append(hits, now)
	if k := msg.IdempotencyKey; k != "" {
		g.seen[k] = now // reserva ANTES de enviar: duas entregas concorrentes não duplicam
	}
	g.sweepLocked(now)
	g.mu.Unlock()

	err := g.next.Send(ctx, msg)

	g.mu.Lock()
	defer g.mu.Unlock()
	if err != nil {
		if k := msg.IdempotencyKey; k != "" {
			delete(g.seen, k) // falhou: a próxima tentativa com a mesma chave pode enviar
		}
		if g.fails++; g.fails >= g.cfg.Prd.BreakerFailures {
			g.openUntil = now.Add(g.cfg.Prd.BreakerCooldown)
			g.fails = 0
		}
		return err
	}
	g.fails = 0
	return nil
}

// pruneWindow descarta os instantes fora da janela (a fatia está em ordem crescente).
func pruneWindow(ts []time.Time, now time.Time, win time.Duration) []time.Time {
	i := 0
	for i < len(ts) && now.Sub(ts[i]) >= win {
		i++
	}
	return ts[i:]
}

// sweepLocked limita a memória do estado de prd: acima de 10 mil chaves, varre as vencidas.
func (g *guarded) sweepLocked(now time.Time) {
	if len(g.hits)+len(g.seen) < 10_000 {
		return
	}
	for a, ts := range g.hits {
		if ts = pruneWindow(ts, now, g.cfg.Prd.Window); len(ts) == 0 {
			delete(g.hits, a)
		} else {
			g.hits[a] = ts
		}
	}
	for k, t := range g.seen {
		if now.Sub(t) >= g.cfg.Prd.Window {
			delete(g.seen, k)
		}
	}
}

// parseRecipient é a validação de endereço de TODOS os ambientes: exatamente UM endereço
// simples. Lista ("a@x, b@y"), nome de exibição, "<>", espaço e CR/LF são recusados — o
// parser por "último @" deixava "vitima@gmail.com, qa@test.dominio" passar pelo domínio de
// teste, e o provider real pode interpretar a lista (ou o CRLF) e entregar de verdade.
func parseRecipient(to string) (addr, domain string, err error) {
	bad := strings.Count(to, "@") != 1 || strings.ContainsAny(to, ", ;<>\"\r\n\t")
	if !bad {
		a, perr := netmail.ParseAddress(to) // import netmail "net/mail" (o pacote se chama mail)
		bad = perr != nil || a.Address != to
	}
	at := strings.LastIndex(to, "@")
	if bad || !strings.Contains(to[at+1:], ".") {
		return "", "", fmt.Errorf("%w: destinatário inválido (precisa ser UM endereço simples)", ErrInvalidRecipient)
	}
	return strings.ToLower(to), strings.ToLower(to[at+1:]), nil
}

// assertTestDomain: fora de prd só passa endereço no domínio de teste (rota nula).
// A mensagem de erro ENSINA o caminho certo (§37, "Culpar o usuário / exigir que ele
// saiba de internals").
func (g *guarded) assertTestDomain(addr, domain string) error {
	for _, t := range g.cfg.TestDomains {
		// domínio exato ou subdomínio dele (test.<domain> cobre a.test.<domain>).
		if domain == t || strings.HasSuffix(domain, "."+t) {
			return nil
		}
	}
	return fmt.Errorf("%w: %s em env=%s. Use <papel>+<run-id>-<n>@%s (null MX) ou registre o ADR de exceção (as 5 condições). Nada foi enviado",
		ErrExternalRecipientBlocked, redact(addr), g.cfg.Env, hintDomain(g.cfg.TestDomains))
}

// redact esconde a parte local do endereço: PII nunca vai crua pra log nem pra erro.
// Só chamar com endereço JÁ validado por parseRecipient (entrada crua pode ter CR/LF).
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
	// O guard embrulha os dois casos. Fora de prd: domínio de teste + cap por execução.
	// Em prd: rate-limit por destinatário + idempotência + breaker; MaxPerRun é IGNORADO.
	return mail.Guarded(base, mail.GuardConfig{
		Env:         cfg.Env,
		TestDomains: cfg.TestMailDomains,
		MaxPerRun:   cfg.MailMaxPerRun, // só não-prd
		Prd:         mail.PrdLimits{}, // zero ⇒ defaults; ajuste por config se o volume pedir
	})
}
```

O caso de uso do OTP recebe `mail.EmailProvider` por injeção e **não conhece ambiente**: ele
só chama `Send` (com `IdempotencyKey` = id do desafio, para a reentrega não duplicar) e
**trata o `error`** (`ErrCircuitOpen`/`ErrRecipientRateLimited` ⇒ enfileira no outbox e
responde 202; nunca perde o OTP). Não existe parâmetro `force`/`skipGuard` — bypass por
argumento é a porta que sempre acaba aberta em produção.

### O teste que vê o vermelho (`internal/platform/mail/guard_test.go`)

```go
// spyProvider conta chamadas: prova que o provider real NÃO foi acionado.
type spyProvider struct {
	calls atomic.Int64
	err   atomic.Pointer[error] // se setado, Send falha com ele
}

func (s *spyProvider) Send(context.Context, mail.Message) error {
	s.calls.Add(1)
	if e := s.err.Load(); e != nil {
		return *e
	}
	return nil
}

var testDomains = []string{"test.exemplo.com.br"}

// TestGuard_RecusaDominioExterno prova o piso: em hml, e-mail pra caixa real é ERRO
// e nada sai. Se este teste ficar verde por acidente (guard removido), o próximo
// laço de carga manda 5.000 e-mails de verdade.
func TestGuard_RecusaDominioExterno(t *testing.T) {
	t.Parallel()

	spy := &spyProvider{}
	provider := mail.Guarded(spy, mail.GuardConfig{Env: mail.EnvHml, TestDomains: testDomains})

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

// TestGuard_RecusaListaEInjecao: o último "@" é de domínio de teste, mas o endereço é uma
// LISTA (ou tem CR/LF). Tem que ser ErrInvalidRecipient, em hml E em prd, sem chamar o provider.
func TestGuard_RecusaListaEInjecao(t *testing.T) {
	t.Parallel()

	for _, env := range []mail.Env{mail.EnvHml, mail.EnvPrd} {
		for _, to := range []string{
			"vitima@gmail.com, qa@test.exemplo.com.br",
			"vitima@gmail.com;qa@test.exemplo.com.br",
			"qa@test.exemplo.com.br\r\nBcc: vitima@gmail.com",
			"Vitima <vitima@gmail.com>",
		} {
			spy := &spyProvider{}
			provider := mail.Guarded(spy, mail.GuardConfig{Env: env, TestDomains: testDomains})

			err := provider.Send(context.Background(), mail.Message{To: to, Subject: "otp", Body: "1"})

			if !errors.Is(err, mail.ErrInvalidRecipient) {
				t.Fatalf("env=%s to=%q: esperava ErrInvalidRecipient; veio %v", env, to, err)
			}
			if got := spy.calls.Load(); got != 0 {
				t.Fatalf("env=%s to=%q: provider chamado %d vez(es); deveria ser 0", env, to, got)
			}
		}
	}
}

// TestGuard_CapAbortaExecucao prova o circuit breaker FORA de prd: o 3º envio com cap=2 falha.
func TestGuard_CapAbortaExecucao(t *testing.T) {
	t.Parallel()

	spy := &spyProvider{}
	provider := mail.Guarded(spy, mail.GuardConfig{Env: mail.EnvHml, TestDomains: testDomains, MaxPerRun: 2})
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

// TestGuard_PrdNaoTemCapPorProcesso é o teste do furo P0-3: o cap de execução em prd derrubava
// o OTP de login depois do 50º envio. Em prd, 500 usuários DIFERENTES recebem o OTP — o
// MaxPerRun=2 (ignorado em prd) não pode barrar nenhum.
func TestGuard_PrdNaoTemCapPorProcesso(t *testing.T) {
	t.Parallel()

	spy := &spyProvider{}
	provider := mail.Guarded(spy, mail.GuardConfig{Env: mail.EnvPrd, MaxPerRun: 2})

	for i := 0; i < 500; i++ {
		to := fmt.Sprintf("user%d@cliente.com.br", i)
		if err := provider.Send(context.Background(), mail.Message{To: to, Subject: "otp", Body: "1"}); err != nil {
			t.Fatalf("envio %d em prd barrado (cap de processo não pode existir em prd): %v", i, err)
		}
	}
	if got := spy.calls.Load(); got != 500 {
		t.Fatalf("provider chamado %d vez(es); deveria ser 500", got)
	}
}

// TestGuard_PrdRateLimitPorDestinatario: o laço que martela UM endereço é contido, e a janela
// deslizante libera de novo depois (relógio injetado, sem sleep).
func TestGuard_PrdRateLimitPorDestinatario(t *testing.T) {
	t.Parallel()

	spy := &spyProvider{}
	now := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	provider := mail.Guarded(spy, mail.GuardConfig{
		Env: mail.EnvPrd, Now: func() time.Time { return now },
		Prd: mail.PrdLimits{PerRecipient: 2, Window: time.Minute},
	})
	msg := mail.Message{To: "ana@cliente.com.br", Subject: "otp", Body: "1"}

	for i := 1; i <= 2; i++ {
		if err := provider.Send(context.Background(), msg); err != nil {
			t.Fatalf("envio %d dentro do limite falhou: %v", i, err)
		}
	}
	if err := provider.Send(context.Background(), msg); !errors.Is(err, mail.ErrRecipientRateLimited) {
		t.Fatalf("esperava ErrRecipientRateLimited no 3º envio; veio %v", err)
	}
	now = now.Add(2 * time.Minute) // a janela venceu
	if err := provider.Send(context.Background(), msg); err != nil {
		t.Fatalf("após a janela deveria liberar; veio %v", err)
	}
	if got := spy.calls.Load(); got != 3 {
		t.Fatalf("provider chamado %d vez(es); deveria ser 3", got)
	}
}

// TestGuard_PrdIdempotencia: a reentrega do mesmo pedido (mesma chave) não duplica o envio.
func TestGuard_PrdIdempotencia(t *testing.T) {
	t.Parallel()

	spy := &spyProvider{}
	provider := mail.Guarded(spy, mail.GuardConfig{Env: mail.EnvPrd})
	msg := mail.Message{To: "ana@cliente.com.br", Subject: "otp", Body: "1", IdempotencyKey: "desafio-123"}

	for i := 0; i < 3; i++ {
		if err := provider.Send(context.Background(), msg); err != nil {
			t.Fatalf("reentrega %d falhou: %v", i, err)
		}
	}
	if got := spy.calls.Load(); got != 1 {
		t.Fatalf("provider chamado %d vez(es); a mesma chave deveria enviar 1", got)
	}
}

// TestGuard_PrdBreakerAbreEFecha: provider caído abre o breaker (falha rápida, sem martelar);
// passado o cooldown, volta a tentar.
func TestGuard_PrdBreakerAbreEFecha(t *testing.T) {
	t.Parallel()

	spy := &spyProvider{}
	down := errors.New("resend 503")
	spy.err.Store(&down)
	now := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	provider := mail.Guarded(spy, mail.GuardConfig{
		Env: mail.EnvPrd, Now: func() time.Time { return now },
		Prd: mail.PrdLimits{BreakerFailures: 2, BreakerCooldown: 30 * time.Second},
	})
	send := func(i int) error {
		return provider.Send(context.Background(),
			mail.Message{To: fmt.Sprintf("u%d@cliente.com.br", i), Subject: "otp", Body: "1"})
	}

	_ = send(1)
	_ = send(2) // 2ª falha seguida: abre
	if err := send(3); !errors.Is(err, mail.ErrCircuitOpen) {
		t.Fatalf("esperava ErrCircuitOpen com o breaker aberto; veio %v", err)
	}
	if got := spy.calls.Load(); got != 2 {
		t.Fatalf("breaker aberto não pode chamar o provider; chamadas=%d, esperado 2", got)
	}
	spy.err.Store(nil)
	now = now.Add(time.Minute) // cooldown venceu
	if err := send(4); err != nil {
		t.Fatalf("após o cooldown deveria voltar a enviar; veio %v", err)
	}
}
```

O mesmo desenho vale para `SmsProvider` (Twilio), `PushProvider` e qualquer webhook de
terceiro: **interface + sink default + guard decorator** (cap por execução fora de prd;
rate-limit/idempotência/breaker em prd). Entregar de verdade fora de
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

- [ ] **Efeito externo fora de prd (§3.1):** `EmailProvider`/`SmsProvider` com **sink default** fora de `prd`, **guard decorator DENTRO do provider** (`mail.Guarded`) devolvendo `error`, **cap por execução SÓ fora de prd** (em prd: rate-limit por destinatário + idempotência + circuit breaker, sem teto de processo), endereço sintético só em `test.<domain>` (null MX) e chave **sandbox** — provado por `TestGuard_RecusaDominioExterno` (espera a recusa), `TestGuard_CapAbortaExecucao` e `TestGuard_PrdNaoTemCapPorProcesso`.
