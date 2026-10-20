## O que muda
<resumo objetivo. Alvo: ≤ 400 linhas alteradas (§24).>

## Por quê
<motivação / ticket>

## Como testei
- [ ] unit + integration passam, cobertura nos mínimos (ver a `schematize-qa`)
- [ ] smoke com asserção de conteúdo + self-check (sem "verde mentiroso")
- [ ] simulated (rotas × personas) — cobertura total
- [ ] pentest de entrada (tipo/sanitização/authz) limpo

## Checklist de padrões
- [ ] Nenhum anti-padrão vetado (§37) no diff
- [ ] Segredo nunca no cliente; auth/authz server-side
- [ ] Migration reversível (se houver schema change)
- [ ] OpenAPI atualizada (se for API)
- [ ] Observabilidade implementada
- [ ] Archive (chat/task) gerado e commitado (§28)
- [ ] ADR criado (se decisão arquitetural ou desvio)
- [ ] CODEOWNERS revisou

## Notas para o reviewer
<pontos de atenção, riscos>
