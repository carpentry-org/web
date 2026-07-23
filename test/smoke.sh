#!/usr/bin/env bash
# end-to-end smoke test: runs test/smoke-server.carp, drives it with curl
set -euo pipefail
cd "$(dirname "$0")/.."

PORT=8437
BASE="http://127.0.0.1:$PORT"
WORK=$(mktemp -d)
LOG=smoke-server.log

echo "smoke: compiling server"
carp -b test/smoke-server.carp

./out/smoke-server > "$LOG" 2>&1 < /dev/null &
SERVER_PID=$!
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  pkill -f 'out/smoke-server' 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

echo "smoke: waiting for server"
up=0
for _ in $(seq 1 90); do
  if curl -sf --max-time 2 "$BASE/ok" >/dev/null 2>&1; then up=1; break; fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then break; fi
  sleep 1
done
if [ "$up" != 1 ]; then
  echo "FAIL: server did not answer; diagnostics follow"
  curl -v --max-time 5 "$BASE/ok" 2>&1 || true
  lsof -nP -i :$PORT 2>&1 || true
  ps aux | grep -E 'smoke-server' | grep -v grep || true
  exit 1
fi

fail() { echo "FAIL: $1"; exit 1; }
check() { echo "smoke: $1"; }

# NUL-free payload (bodies pass through String). No pipe here may have an
# early-closing reader: CI runners ignore SIGPIPE, and macOS tr/base64 spin
# forever on EPIPE, which hung this step at the job timeout three times.
head -c 75000 /dev/urandom | base64 > "$WORK/b64"
head -c 100000 "$WORK/b64" > "$WORK/body"
check "payload ready ($(wc -c < "$WORK/body") bytes)"

# 1. basic GET
check "GET /ok"
[ "$(curl -sf --max-time 10 "$BASE/ok")" = "ok" ] || fail "GET /ok"

# 2. a 100KB body arrives whole (the original >4KB truncation bug)
check "100KB upload"
curl -sf --max-time 30 --data-binary @"$WORK/body" \
  -H 'Content-Type: application/octet-stream' \
  -o "$WORK/echo" "$BASE/echo" || fail "100KB POST errored"
cmp -s "$WORK/body" "$WORK/echo" || fail "100KB body was not echoed intact"

# 3. a chunked body is reassembled and decoded before dispatch
check "chunked upload"
curl -sf --max-time 30 -H 'Transfer-Encoding: chunked' \
  --data-binary @"$WORK/body" -o "$WORK/chunked" "$BASE/echo" \
  || fail "chunked POST errored"
cmp -s "$WORK/body" "$WORK/chunked" || fail "chunked body was not decoded intact"

# 4. normalization: the handler sees a plain body with a Content-Length
check "normalization"
META=$(curl -sf --max-time 10 -H 'Transfer-Encoding: chunked' \
  --data-binary 'hello world' "$BASE/meta")
[ "$META" = "plain 11" ] || fail "normalization (got: $META)"

# 5. the server answers Expect: 100-continue with an interim response
check "100-continue"
curl -sf --max-time 30 -H 'Expect: 100-continue' \
  --data-binary @"$WORK/body" -o /dev/null "$BASE/echo" -v 2> "$WORK/expect.log" \
  || fail "expect POST errored"
grep -q 'HTTP/1.1 100 Continue' "$WORK/expect.log" \
  || fail "no 100 Continue interim response"

# 6. keep-alive: two requests reuse one connection
check "keep-alive"
curl -sf --max-time 10 -o /dev/null -o /dev/null -v "$BASE/ok" "$BASE/ok" \
  2> "$WORK/ka.log" || fail "keep-alive requests errored"
grep -qi 're-us' "$WORK/ka.log" || fail "connection was not reused"

# 7. malformed framing is rejected with a 400
check "malformed framing"
CODE=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
  -H 'Transfer-Encoding: gzip' --data-binary 'x' "$BASE/echo")
[ "$CODE" = "400" ] || fail "non-chunked Transfer-Encoding not rejected (got: $CODE)"

# 8. a byte range yields 206 Partial Content with the requested bytes
check "byte range"
RH=$(curl -s --max-time 10 -D - -o "$WORK/range" -r 0-4 "$BASE/static/index.html")
echo "$RH" | grep -qi '206 Partial Content' || fail "range request not 206"
echo "$RH" | grep -qi 'Content-Range: bytes 0-4/11' || fail "wrong Content-Range"
[ "$(cat "$WORK/range")" = "root " ] || fail "range body wrong (got: $(cat "$WORK/range"))"

# 9. an open-ended range reassembles to the whole file
check "open range"
[ "$(curl -s --max-time 10 -r 0- "$BASE/static/index.html")" \
  = "$(cat test/static-fixtures/index.html)" ] || fail "open range mismatch"

# 10. a range past the end is rejected with 416
check "unsatisfiable range"
CODE=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
  -r 100-200 "$BASE/static/index.html")
[ "$CODE" = "416" ] || fail "unsatisfiable range not 416 (got: $CODE)"

echo "smoke: all checks passed"
