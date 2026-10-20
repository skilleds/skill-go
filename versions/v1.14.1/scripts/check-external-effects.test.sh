#!/usr/bin/env bash
# herdado de schematize-engineering — não edite aqui (fonte: skill-engineering/scripts/check-external-effects.test.sh; regenere: node tools/sync-herdados.mjs)
# check-external-effects.test.sh — o VERMELHO VISTO do gate de efeito externo.
#
# Motivo: o gate existia em UM lugar (schematize-engineering) e NUNCA tinha reprovado de proposito.
# Piso sem vermelho visto e prosa: o ADR-0004 nasceu de um incidente de >5.000 e-mails, e um gate
# que nunca travou nao prova nada. Este teste planta cada uma das violacoes e exige exit 1.
# Entrada: nenhuma. Saida: exit 0 todos os casos passam - exit 1 algum caso falhou.
# EXCEÇÃO DECLARADA de strict mode (`schematize-shell` -> `references/piso.md` secao 1):
# harness de teste roda sem `-e` de propósito — ele precisa continuar depois de um caso
# vermelho para reportar TODOS, em vez de parar no primeiro.
set -uo pipefail
G="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-external-effects.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
rc=0

echo "── projeto limpo passa"
P="$W/limpo"; mkdir -p "$P/test"
printf 'user = "qa+1@test.exemplo.test"\n' > "$P/test/seed.sql"
printf 'APP_ENV=dev\nRESEND_API_KEY=re_sandbox_xxx\nMAIL_MAX_PER_RUN=50\n' > "$P/.env"
OUT=$(bash "$G" "$P" 2>&1); z=$?
if [ "$z" -eq 0 ]; then echo "  ✔ exit 0"; else echo "  ✖ exit $z: $OUT"; rc=1; fi

echo "── e-mail de CAIXA REAL em seed BLOQUEIA (o acidente das 5.000 mensagens)"
P="$W/real"; mkdir -p "$P/test"
printf "INSERT INTO users (email) VALUES ('fulano@gmail.com');\n" > "$P/test/seed.sql"
OUT=$(bash "$G" "$P" 2>&1); z=$?
if [ "$z" -eq 1 ] && grep -q 'caixa REAL' <<<"$OUT"; then echo "  ✔ exit 1"; else echo "  ✖ exit $z: $OUT"; rc=1; fi

echo "── chave de provedor NAO-sandbox em .env de dev BLOQUEIA"
P="$W/chave"; mkdir -p "$P"
printf 'APP_ENV=hml\nRESEND_API_KEY=re_live_abc123def456\nMAIL_MAX_PER_RUN=50\n' > "$P/.env"
OUT=$(bash "$G" "$P" 2>&1); z=$?
if [ "$z" -eq 1 ] && grep -q 'credencial de provedor' <<<"$OUT"; then echo "  ✔ exit 1"; else echo "  ✖ exit $z: $OUT"; rc=1; fi

echo "── .env SEM ambiente declarado e tratado como NAO-prd (fail-closed)"
P="$W/semenv"; mkdir -p "$P"
printf 'RESEND_API_KEY=re_live_abc123def456\nMAIL_MAX_PER_RUN=50\n' > "$P/.env"
OUT=$(bash "$G" "$P" 2>&1); z=$?
if [ "$z" -eq 1 ]; then echo "  ✔ exit 1 (config ausente nao vira permissao)"; else echo "  ✖ exit $z: $OUT"; rc=1; fi

echo "── envio configurado SEM cap por execucao avisa"
P="$W/semcap"; mkdir -p "$P"
printf 'APP_ENV=dev\nSMTP_HOST=localhost\n' > "$P/.env"
OUT=$(bash "$G" "$P" 2>&1)
if grep -q 'cap por execução' <<<"$OUT"; then echo "  ✔ avisou"; else echo "  ✖ silencio: $OUT"; rc=1; fi

echo "── ambiente de PRODUCAO nao e barrado pela regra de chave"
P="$W/prd"; mkdir -p "$P"
printf 'APP_ENV=production\nRESEND_API_KEY=re_live_abc123def456\nMAIL_MAX_PER_RUN=50\n' > "$P/.env"
OUT=$(bash "$G" "$P" 2>&1); z=$?
if [ "$z" -eq 0 ]; then echo "  ✔ exit 0 (o piso e sobre NAO-producao)"; else echo "  ✖ exit $z: $OUT"; rc=1; fi

echo
[ $rc -eq 0 ] && echo "✔ check-external-effects.test.sh: todos os casos" || echo "✖ check-external-effects.test.sh: falhou"
exit $rc
