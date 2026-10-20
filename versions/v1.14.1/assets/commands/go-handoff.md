---
description: Gera o handoff de contexto (context.md + checklist.md) no archive, SEM compactar
argument-hint: "[foco opcional]"
---

Gere o **handoff de contexto** desta sessão (§34.1, §28) **sem** compactar — use
pra fechar um marco, fim de sessão ou troca de tarefa. Se houver $ARGUMENTS, use
como foco.

1. Use `${PROJECT_ARCHIVE:-<projeto>_archive/context}` e timestamp `<ts>` = `YYYY-MM-DD-HH-MM-SS`.
2. Escreva `<ts>-context.md`: objetivo da sessão, decisões e porquê, componentes/
   arquivos tocados (com caminho), estado atual (funciona / quebrado / pendente),
   threads em aberto, como retomar (comandos/setup/env).
3. Escreva `<ts>-checklist.md`: `## FEITO` (detalhado, pra não refazer), `## EM
   ABERTO / A FAZER` (próximo passo concreto + arquivo + critério de pronto),
   `## NÃO REFAZER` (becos descartados e porquê).
4. Confirme os dois caminhos. **Não rode `/compact`** — este comando só arquiva.

Regras: armazene SEMPRE em `<projeto>_archive` (§28). Sem segredo/PII nos MDs (§16.1).
