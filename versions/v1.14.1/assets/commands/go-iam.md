---
description: schematize-go — força/audita/scaffolda o IAM da casa (identidade≠email, ≥2 fatores, ReBAC multi-tenant, sessão longa/logout irreversível) como microserviço Go separado em auth.<domain>, ou atualiza um auth existente
argument-hint: "[bootstrap | audit | migrate]"
---

Governe identidade e autorização pelo padrão IAM da casa (`references/iam.md`), no recorte
**backend/Go**. Plan-first: **audita, mostra o plano, pede aprovação, então executa.** Use
este comando para **forçar só a parte de IAM** num projeto (novo ou existente) ou
**atualizar/portar um auth legado**.

## 0. Modo
- `audit` — varre o projeto e reporta o gap contra o piso IAM (checklist §iam).
- `bootstrap` — scaffolda o IAM do zero como **microserviço Go separado**.
- `migrate` — porta um auth legado pro IAM (**prioridade 0**, strangler-fig).

## 1. Topologia primeiro (inegociável)
Confirme/scaffolde que o auth é **aplicação SEPARADA** (`references/iam.md` §1):
- Microserviço **Go** próprio `<projeto>_auth_go` + front próprio `<projeto>_authfront`,
  servidos em **`auth.<domain>`** — **VETADO** monolith apensado (nem `internal/auth` do
  serviço principal).
- Repo/deploy/**user Linux + systemd isolados** por conta própria (casa com `schematize-engineering` -> `ops.md` §3).
- App principal e clientes **delegam por OIDC/OAuth2.1 + PKCE**; a **chave de assinatura só
  no auth Go**, consumidores validam por **JWKS público** (middleware Go cacheando o JWKS).

## 2. Identidade
- **ID interno imutável** (ULID/UUIDv7) como `sub`; **email/telefone nunca são ID**; **N
  emails** por usuário (incentivado; entidades filhas com `VerifiedAt`, nunca a PK).
  Identificador só vale **verificado**.
- **SSO com recuperação local forçada**; account-linking explícito (anti-takeover).
- **Nudge de email secundário:** detecta provedor e recomenda outro provedor + tooltip "i".

## 3. Fatores (≥2 sempre)
- **Passkey/WebAuthn no núcleo** (lib madura, ex. `go-webauthn`); TOTP (`pquerna/otp`)/push;
  **email OTP (Resend) always-on inclusive HML** (só operador desliga); **Twilio** p/
  telefone; providers **plugáveis como interfaces Go** (`EmailProvider`/`SmsProvider`/
  `PushProvider`, adaptadores na borda).
- **Senha por padrão** (**argon2id** via `x/crypto/argon2` + HIBP), **opcional no seletor**.
- **Senha + Email OTP JÁ é o 2FA baseline** (acesso pleno desde o cadastro). Fator forte (passkey/TOTP) é **nudge + step-up just-in-time** (op sensível / risco), **NUNCA muro pré-login** — barrar o acesso por falta de fator forte é o círculo infinito / bug de bootstrap **VETADO** pela norma (`iam.md` §3/§4).
  middleware barra o token de bootstrap fora do enrolamento).
- Invariante de troca: **mutar fator X exige fator Y≠X no maior AAL**; notificar canais;
  remover último fator forte = **atraso cancelável** (job agendado). Recuperação **≥ login**.

## 4. Autorização (multi-tenant, ReBAC)
- **Identidade global, papéis por tenant** (membership). Motor **ReBAC (OpenFGA/SpiceDB)** —
  o auth Go **fala com o motor via client**, não implementa authz na mão; tuplas
  `(objeto, relação, usuário)`; **RBAC granular** (`recurso:ação`, papéis customizados) +
  **ABAC** (conditional tuples). **PDP = Check API / PEP = middleware Go, deny-default,
  enforcement server-side, token fino, decisão auditada.** Escrita de tupla via outbox
  (nunca dual-write solto).

## 5. Sessão / logout
- **Multi-dispositivo** + **view de remover dispositivos** + "sair de todos" (session store
  Postgres+Redis, 1 linha por sessão com `refresh_family_id`/`device_id`/`jti`).
- **Sessão 7 dias por padrão; pergunta se confiável → 90 dias** (access token curto com
  refresh silencioso rotativo — nada de "15 min e é chutado"). Step-up fresco em ops
  sensível. Refresh opaco (`crypto/rand`), reuso → revoga a **família**.
- **Botão Sair visível → kill IRREVERSÍVEL:** revoga refresh + família, apaga sessão
  server-side, `jti` na **denylist** (Redis/DB, consultada em toda request), desassocia push
  token. Nada recria a sessão.

## 6. Testes (dispare o gate do pentest)
Rode/priorize a rotina agressiva (`schematize-pentest`): **cross-tenant (BOLA/IDOR),
priv-esc (BFLA), abuso de fluxo (bypass 2FA/reset/step-up, replay, refresh reuse, JWT
alg=none/kid, logout que não invalidou)** — gate que trava em vazamento. Ver `/pentest-authz`.

## 7. Migração de legado (modo `migrate`, prioridade 0)
Strangler-fig: dual-run, **re-hash preguiçoso** (→argon2id) no login, mapeia registros →
modelo novo (dedupe emails, cunha IDs ULID/UUIDv7), **no 1º login pós-migração: nudge + step-up (nunca barra o acesso por falta de fator forte)**, **revoga
sessões legadas**, **re-deriva authz** em tuplas ReBAC (nunca confia na antiga). O auth
migrado nasce microserviço Go separado. (Legado Node casa com `schematize-node`.)

## 8. Saída
Grave o plano/relatório em `<projeto>_archive/` (§28): topologia (app separada?), gaps do
checklist IAM (`references/iam.md`), plano por fase (F0–F6) e — se `migrate` — o mapa
legado→novo e a ordem de corte. Confirme: auth é microserviço Go à parte? identidade≠email?
≥2 fatores? ReBAC multi-tenant deny-default? sessão longa + logout irreversível? testes
cross-tenant no CI?
