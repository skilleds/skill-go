#!/usr/bin/env bash
# smoke-selfcheck.test.sh — vermelho e verde plantados do smoke-selfcheck.sh.
# O quê: sobe um servidor HTTP local de brinquedo e prova que (1) o smoke passa com API sã,
#   (2) reprova com canário 404 respondendo 200 e com API fora do ar, (3) o --self-check sai 0
#   quando o runner reporta a falha forçada e sai 1 quando o runner é CEGO (test_fail anulado).
# Saída: exit 0 se todos os casos passam, 1 se algum falhou.
# strict-ok: harness de teste — roda TODOS os casos e soma; com `-e` pararia no primeiro vermelho (`schematize-shell` -> `references/piso.md` secao 1)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$(mktemp -d)"; PIDS=()
limpa() { local p; for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$W"; }
trap limpa EXIT
rc=0

command -v python3 >/dev/null && command -v curl >/dev/null || { echo "smoke-selfcheck.test: SKIP (precisa de python3 e curl)"; exit 0; }

cat > "$W/srv.py" <<'PY'
import sys, http.server
mode, portfile = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if mode == "catchall" or self.path == "/ready":
            code = 200
        else:
            code = 404
        self.send_response(code); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(portfile, "w").write(str(s.server_address[1]))
s.serve_forever()
PY
serve() { # serve modo -> define URL (sem $(...): o servidor em background seguraria o pipe)
  rm -f "$W/port"; python3 "$W/srv.py" "$1" "$W/port" >/dev/null 2>&1 & PIDS+=($!)
  for _ in $(seq 1 50); do [ -s "$W/port" ] && break; sleep 0.1; done
  URL="http://127.0.0.1:$(cat "$W/port")"
}
expect() { # expect "descrição" rc_esperado rc_real saída [padrão]
  local d="$1" want="$2" got="$3" out="$4" pat="${5:-}"
  if [ "$got" -eq "$want" ] && { [ -z "$pat" ] || grep -q -- "$pat" <<<"$out"; }; then
    echo "  ok  $d"
  else
    echo "  FALHOU $d (rc=$got, esperado $want)"; echo "$out" | sed 's/^/      /'; rc=1
  fi
}

serve sane; GOOD="$URL"; serve catchall; BAD="$URL"
DEAD="http://127.0.0.1:1"   # porta 1: nada escuta

echo "── VERDE: API sã"
out=$(API_BASE="$GOOD" bash "$HERE/smoke-selfcheck.sh"); expect "modo normal passa" 0 $? "$out" "OK smoke/self-check"
out=$(API_BASE="$GOOD" bash "$HERE/smoke-selfcheck.sh" --self-check); expect "--self-check prova que sabe falhar (exit 0)" 0 $? "$out" "self-check OK"

echo "── VERMELHO: canário 404 respondido com 200 (catch-all)"
out=$(API_BASE="$BAD" bash "$HERE/smoke-selfcheck.sh"); expect "catch-all reprova" 1 $? "$out" "404"

echo "── VERMELHO: API fora do ar (000 não vira verde)"
out=$(API_BASE="$DEAD" bash "$HERE/smoke-selfcheck.sh"); expect "sem API reprova" 1 $? "$out" "FALHA"
out=$(API_BASE="$DEAD" bash "$HERE/smoke-selfcheck.sh" --self-check); expect "--self-check segue 0 mesmo com API fora (a falha forçada foi vista)" 0 $? "$out"

echo "── VERMELHO: runner CEGO (test_fail anulado) — o --self-check tem que gritar"
mkdir -p "$W/cego"; cp "$HERE/smoke-selfcheck.sh" "$W/cego/"
cp "$HERE/lib.sh" "$W/cego/lib.sh"
printf '\ntest_fail() { :; }\n' >> "$W/cego/lib.sh"
out=$(API_BASE="$GOOD" bash "$W/cego/smoke-selfcheck.sh" --self-check); expect "smoke cego sai 1" 1 $? "$out" "SMOKE CEGO"

[ "$rc" -eq 0 ] && echo "smoke-selfcheck.test: OK" || echo "smoke-selfcheck.test: FALHOU"
exit "$rc"
