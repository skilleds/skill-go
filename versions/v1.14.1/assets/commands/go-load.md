---
description: schematize-go — carrega à força TODO o corpo normativo (DDD/arquitetura, clean code, segurança, dados, testes, operação) no contexto e passa a aplicá-lo no projeto atual como regra inegociável
---

Carregue **à força** e passe a aplicar **integralmente** os Padrões de Engenharia da Casa (skill `schematize-go`) neste projeto. A partir de agora, nesta sessão, isto **não é opcional**.

1. **Leia agora, na íntegra, TODOS os arquivos** de references da skill — não trabalhe de memória, abra cada arquivo. O caminho é `.claude/skills/schematize-go/references/*.md` (instalação no projeto) ou `~/.claude/skills/schematize-go/references/*.md` (instalação global). Com destaque para:
   - `padroes-codigo.md` — **clean code**: arquivo ≤750 linhas (~500 úteis + ~250 comentário; flag >300 úteis, ~400 obs), uma função/unidade por arquivo, doc-comment obrigatório (motivo/comportamento/I-O), `MAPA.md`.
   - `arquitetura.md` — **DDD**, camadas, repositórios, bounded contexts, anti-monólito, shared libs, CQRS, escolha de linguagem.
   - `seguranca.md` — auth/JWT, multi-tenancy, LGPD, segredo nunca no cliente, SQL parametrizado.
   - `iam.md` — **IAM da casa (recorte Go)**: auth como microserviço Go separado (`auth.<domain>`), ID≠email, ≥2 fatores (passkey/Resend/Twilio), ReBAC multi-tenant deny-default (PEP=middleware Go), sessão 7d/90d, logout irreversível, migração de legado prioridade 0.
   - `dados-eventos.md` — eventos/mensageria, banco, cache, APIs, resiliência, jobs.
   - `cadeia-suprimentos.md` — lockfile, SBOM, scan que trava, imagem mínima/pinada/assinada, SLSA.
   - `testes.md` — test kit, "verde de verdade", pentest, Q.A. plan-first.
   - `observabilidade.md` — healthchecks, performance, FinOps.
   - `operacao.md` + `entrega.md` — config, deploy/K8s, git/PR, runbooks, ADR, **archive**, DoD, índice.
   - `ops.md` — **control plane `<projeto>_ops`**: fluxo dev→local→github→hml→prd (nada direto no servidor), ops como interface única (100%, autônomo), instalação paralela=`nproc`, independência=invariante (prioridade máxima).
   - `anti-padroes.md` — a lista completa de anti-padrões vetados (§37).
   - `contexto-claude-code.md` — gestão de contexto/handoff em sessões longas.

2. **Confirme ao usuário** que leu, com **1 linha por arquivo** resumindo o piso central de cada um.

3. Deste ponto em diante, **aplique estes padrões como regra inegociável** em toda decisão, geração e revisão de código deste projeto — arquitetura/DDD, clean code, segurança, testes e archive. Em conflito entre "fazer rápido" e o padrão, **o padrão vence**.

4. **Atualize o `CLAUDE.md` da raiz** do repositório com a versão atual de `assets/CLAUDE.md` da skill — **sobrescreva mesmo se já existir** (rodar não pode deixar a versão antiga). Se o `CLAUDE.md` atual tiver customização local (seções fora do template da skill), salve backup `./CLAUDE.md.bak` e reaplique as customizações por cima do template novo. Se não existir, crie. É o mesmo que o comando `/go-claude`. Confirme a versão aplicada.
