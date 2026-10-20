# Índice de Microfunções — <serviço>

> Catálogo fino de funções/módulos (§39), idealmente **gerado** a partir dos
> doc-comments obrigatórios (§6) via `scripts/build-index.mjs`. NÃO editar à mão
> as seções geradas — corrija o doc-comment na origem e regenere.
> Local: `<projeto>_archive/index/INDEX_FUNCTIONS.md`. Última geração: <data>.

## <módulo / pasta>

| Função | O quê | Onde é usada / prevista | Efeitos | Origem |
|---|---|---|---|---|
| `createOrder` | valida payload e cria pedido | use-case CreateOrder; handler POST /v1/checkout | persiste orders, publica evento via outbox | `application/order/create.ts:14` |
| ... | ... | ... | ... | ... |

<!-- BEGIN GENERATED -->
<!-- conteúdo gerado por build-index; não editar manualmente -->
<!-- END GENERATED -->
