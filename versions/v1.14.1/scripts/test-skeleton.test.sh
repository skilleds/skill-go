#!/usr/bin/env bash
# test-skeleton.test.sh — vermelho e verde plantados do esqueleto de teste (test-skeleton.sh).
# O quê: o esqueleto é a base que todo script de teste copia; se ele aceitar API quebrada o
#   erro se multiplica. Sobe um servidor de brinquedo e prova que o esqueleto passa com resposta
#   sã e REPROVA 500, corpo sem dados e vazamento de stack trace.
# Layout exigido pelo esqueleto: <dir>/lib.sh e <dir>/tests/<script>.sh.
# Saída: exit 0 se todos os casos passam, 1 se algum falhou.
# strict-ok: harness de teste — roda TODOS os casos e soma; com `-e` pararia no primeiro vermelho (`schematize-shell` -> `references/piso.md` secao 1)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$(mktemp -d)"; PIDS=()
limpa() { local p; for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$W"; }
trap limpa EXIT
rc=0

command -v python3 >/dev/null && command -v curl >/dev/null && command -v jq >/dev/null \
  || { echo "test-skeleton.test: SKIP (precisa de python3, curl e jq)"; exit 0; }

mkdir -p "$W/app/tests"; cp "$HERE/lib.sh" "$W/app/lib.sh"; cp "$HERE/test-skeleton.sh" "$W/app/tests/skel.sh"

cat > "$W/srv.py" <<'PY'
import sys, http.server
mode, portfile = sys.argv[1], sys.argv[2]
BODY = {"good": b'{"data":[{"id":1}]}', "empty": b'{"data":[]}', "leak": b'{"data":[1],"err":"stacktrace at foo"}', "boom": b'{}'}[mode]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(500 if mode == "boom" else 200)
        self.send_header("Content-Length", str(len(BODY))); self.end_headers(); self.wfile.write(BODY)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(portfile, "w").write(str(s.server_address[1]))
s.serve_forever()
PY
serve() {
  rm -f "$W/port"; python3 "$W/srv.py" "$1" "$W/port" >/dev/null 2>&1 & PIDS+=($!)
  for _ in $(seq 1 50); do [ -s "$W/port" ] && break; sleep 0.1; done
  URL="http://127.0.0.1:$(cat "$W/port")"
}
expect() {
  local d="$1" want="$2" got="$3" out="$4" pat="${5:-}"
  if [ "$got" -eq "$want" ] && { [ -z "$pat" ] || grep -q -- "$pat" <<<"$out"; }; then
    echo "  ok  $d"
  else
    echo "  FALHOU $d (rc=$got, esperado $want)"; echo "$out" | sed 's/^/      /'; rc=1
  fi
}
run() { API_BASE="$1" bash "$W/app/tests/skel.sh" 2>&1; }

echo "── VERDE: resposta sã com dados"
serve good; out=$(run "$URL"); expect "200 com data passa" 0 $? "$out" "OK"

echo "── VERMELHO: status inesperado (500)"
serve boom; out=$(run "$URL"); expect "500 reprova" 1 $? "$out" "esperado"

echo "── VERMELHO: 200 mas sem dados (status não basta)"
serve empty; out=$(run "$URL"); expect "data vazio reprova" 1 $? "$out" "sem 'data'"

echo "── VERMELHO: vazamento de stack trace no corpo"
serve leak; out=$(run "$URL"); expect "stacktrace reprova" 1 $? "$out" "vazou"

echo "── VERMELHO: API fora do ar"
out=$(run "http://127.0.0.1:1"); expect "sem API reprova" 1 $? "$out"

[ "$rc" -eq 0 ] && echo "test-skeleton.test: OK" || echo "test-skeleton.test: FALHOU"
exit "$rc"
