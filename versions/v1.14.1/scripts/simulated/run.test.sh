#!/usr/bin/env bash
# run.test.sh — o VERMELHO VISTO do motor simulated (A1 e A4 da vistoria de 2026-08-21).
#
# Motivo: `ghost = []  # TODO` deixava `len(ghost) == 0` VACUAMENTE verdadeiro, e a cobertura total
# passava sempre — contra o MUST de `schematize-qa` -> `references/categorias.md` ("rota fantasma e rota morta quebram
# o run"). E `classify` consultava a constante DEFAULT_PERSONAS em vez do `personas` carregado, o
# que fazia toda persona customizada virar suspeita de vazamento cross-tenant.
# Gate que nunca reprovou nao e gate: este teste sobe um alvo de mentira e exige o vermelho.
# Entrada: nenhuma. Saida: exit 0 todos os casos passam - exit 1 algum caso falhou.
# strict-ok: harness de teste — continua depois de um caso vermelho para reportar todos (`schematize-shell` -> `references/piso.md` secao 1)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; [ -n "${SRV:-}" ] && kill "$SRV" 2>/dev/null' EXIT
PORT="${PORT:-13977}"
rc=0

# --- alvo de mentira: serve /a e /b e um OpenAPI que declara os dois -----------------
cat > "$WORK/alvo.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
SPEC = {"paths": {"/a": {"get": {}}, "/b": {"get": {}}}}
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path == "/openapi.json":
            b = json.dumps(SPEC).encode()
        elif self.path in ("/a", "/b"):
            b = b'{"ok":true}'
        else:
            self.send_response(404); self.send_header("Content-Length", "0"); self.end_headers(); return
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
python3 "$WORK/alvo.py" "$PORT" & SRV=$!
for _ in $(seq 1 50); do curl -sf "http://127.0.0.1:$PORT/a" >/dev/null 2>&1 && break; sleep 0.1; done

run_sim() { # run_sim <dir-de-config> -> imprime a saida, devolve o exit code
  cp "$HERE/run.py" "$1/run.py"
  ( cd "$1" && PROJECT_TEST_API_BASE="http://127.0.0.1:$PORT" PROJECT_TEST_LOG_DIR="$1/logs" \
      PROJECT_SIM_SKIP_MUTATIONS=1 python3 run.py 2>&1 )
}

echo "── PRE-FLIGHT: run que MUTA sem provider sink ABORTA antes do 1o request"
PF="$WORK/preflight"; mkdir -p "$PF"
cp "$HERE/run.py" "$PF/run.py"
printf '[{"method":"POST","path":"/a","category":"public","mutates":true}]\n' > "$PF/routes.json"
printf '{"anon":{"token":null,"expected_access":["public"]}}\n' > "$PF/personas.json"
OUT=$( cd "$PF" && APP_ENV=hml PROJECT_TEST_API_BASE="http://127.0.0.1:$PORT" python3 run.py 2>&1 ); z=$?
if [ "$z" -eq 1 ] && grep -q 'PRÉ-FLIGHT FALHOU' <<<"$OUT" && grep -q 'MAIL_PROVIDER' <<<"$OUT"; then
  echo "  ✔ exit 1 e nada foi executado (o padrao do incidente das 5.000 mensagens)"
else echo "  ✖ rodou mesmo assim: $OUT"; rc=1; fi

echo "── PRE-FLIGHT: com sink + dominio + cap, o run PROSSEGUE"
OUT=$( cd "$PF" && APP_ENV=hml MAIL_PROVIDER=sink TEST_MAIL_DOMAIN=test.acme.com MAIL_MAX_PER_RUN=50 \
       PROJECT_TEST_API_BASE="http://127.0.0.1:$PORT" PROJECT_TEST_LOG_DIR="$PF/logs" python3 run.py 2>&1 )
if ! grep -q 'PRÉ-FLIGHT FALHOU' <<<"$OUT"; then echo "  ✔ passou do pre-flight"; else echo "  ✖ barrou indevidamente: $OUT"; rc=1; fi

echo "── PRE-FLIGHT: producao exige confirmacao explicita"
OUT=$( cd "$PF" && APP_ENV=production MAIL_PROVIDER=sink TEST_MAIL_DOMAIN=test.acme.com MAIL_MAX_PER_RUN=50 \
       PROJECT_TEST_API_BASE="http://127.0.0.1:$PORT" python3 run.py 2>&1 ); z=$?
if [ "$z" -eq 1 ] && grep -q 'PROJECT_SIM_ALLOW_PRD' <<<"$OUT"; then
  echo "  ✔ exit 1 sem PROJECT_SIM_ALLOW_PRD=1"
else echo "  ✖ rodou em prd sem confirmacao: $OUT"; rc=1; fi

echo "── A1: rota FANTASMA plantada (servida, fora do catalog) reprova"
G="$WORK/ghost"; mkdir -p "$G"
printf '[{"method":"GET","path":"/a","category":"public","mutates":false}]\n' > "$G/routes.json"
printf '{"anon":{"token":null,"expected_access":["public"]}}\n' > "$G/personas.json"
OUT="$(run_sim "$G")"; z=$?
if [ "$z" -eq 1 ] && grep -q 'ghost=1' <<<"$OUT"; then echo "  ✔ exit 1 e ghost=1 (/b servida e fora do catalog)"; else echo "  ✖ saiu $z: $OUT"; rc=1; fi

echo "── A1b: catalog completo (sem fantasma, sem morta) passa"
K="$WORK/ok"; mkdir -p "$K"
printf '[{"method":"GET","path":"/a","category":"public","mutates":false},{"method":"GET","path":"/b","category":"public","mutates":false}]\n' > "$K/routes.json"
printf '{"anon":{"token":null,"expected_access":["public"]}}\n' > "$K/personas.json"
OUT="$(run_sim "$K")"; z=$?
if [ "$z" -eq 0 ] && grep -q 'cobertura=total' <<<"$OUT"; then echo "  ✔ exit 0 e cobertura=total"; else echo "  ✖ saiu $z: $OUT"; rc=1; fi

echo "── A1c: SEM fonte de rotas servidas, cobertura NAO pode ser total (o verde vacuo)"
N="$WORK/nosrc"; mkdir -p "$N"
cp "$K/routes.json" "$N/routes.json"; cp "$K/personas.json" "$N/personas.json"
OUT="$( cp "$HERE/run.py" "$N/run.py"; cd "$N" && PROJECT_TEST_API_BASE="http://127.0.0.1:$PORT" \
  PROJECT_SIM_SERVED_URL="http://127.0.0.1:$PORT/nao-existe" PROJECT_TEST_LOG_DIR="$N/logs" \
  PROJECT_SIM_SKIP_MUTATIONS=1 python3 run.py 2>&1 )"; z=$?
if [ "$z" -eq 1 ] && grep -q 'INDISPONIVEL' <<<"$OUT"; then echo "  ✔ exit 1 e reconciliacao INDISPONIVEL (nao vira cobertura total)"; else echo "  ✖ saiu $z: $OUT"; rc=1; fi

echo "── A4: persona CUSTOMIZADA nao vira falso positivo de vazamento"
P="$WORK/persona"; mkdir -p "$P"
cp "$K/routes.json" "$P/routes.json"
printf '{"cliente_pj":{"token":null,"expected_access":["public"]}}\n' > "$P/personas.json"
OUT="$(run_sim "$P")"; z=$?
if [ "$z" -eq 0 ] && grep -q 'REVIEW=0' <<<"$OUT"; then echo "  ✔ persona 'cliente_pj' (fora de DEFAULT_PERSONAS) sem REVIEW"; else echo "  ✖ saiu $z: $OUT"; rc=1; fi

echo "── A4b: persona SEM contrato de acesso vira REVIEW explicito, nao silencio"
Q="$WORK/sem"; mkdir -p "$Q"
cp "$K/routes.json" "$Q/routes.json"
printf '{"cliente_pj":{"token":null}}\n' > "$Q/personas.json"
OUT="$(run_sim "$Q")"; z=$?
if [ "$z" -eq 1 ] && grep -q 'REVIEW=2' <<<"$OUT"; then echo "  ✔ 2 REVIEW ('sem contrato de acesso')"; else echo "  ✖ saiu $z: $OUT"; rc=1; fi

echo
[ $rc -eq 0 ] && echo "✔ simulated/run.test.sh: todos os casos" || echo "✖ simulated/run.test.sh: falhou"
exit $rc
