---
description: Q.A. no contexto Go — aplica a disciplina da skill schematize-qa (/qa-plan → /qa-run) com as ferramentas de teste de Go
argument-hint: "[escopo: unit|smoke|security|e2e|all|full|...]"
---

Conduza o **Q.A. no contexto Go** aplicando a disciplina da skill dedicada **schematize-qa**
(o fluxo plan-first `/qa-plan` → `/qa-run`: planeja tudo, gera o MD de passo a passo, **pede
aprovação antes de rodar**, executa faseado/assistido ou de uma vez com watchdog, coleta
`summary.json` e trava nos gates).

No recorte **Go**, use as ferramentas de teste da linguagem — `go test -race`, `go test -cover`,
tabelas de teste, `testing`/`testify`, fuzzing (`go test -fuzz`), `httptest`, os scripts de teste
da skill (`scripts/`) e o pentest da schematize-pentest.

Rode `/qa-plan` para planejar e aprovar, depois `/qa-run` para executar. Nada de Q.A. roda sem
plano aprovado registrado no `<projeto>_archive/qa/`.
