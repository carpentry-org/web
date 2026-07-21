#!/usr/bin/env bash
# end-to-end smoke test: runs test/smoke-server.carp, drives it with curl
set -euo pipefail
cd "$(dirname "$0")/.."

PORT=8437
BASE="http://127.0.0.1:$PORT"
WORK=$(mktemp -d)

# the server must not inherit this script's stdout/stderr: a surviving child
# holding them open keeps a CI step running until the job timeout
carp -x test/smoke-server.carp > "$WORK/server.log" 2>&1 < /dev/null &
SERVER_PID=$!
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  pkill -f 'out/smoke-server' 2>/dev/null || true
  echo "--- server log ---"
  cat "$WORK/server.log" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "smoke: waiting for server (carp compiles first)"
up=0
for _ in $(seq 1 300); do
  if curl -sf --max-time 2 "$BASE/ok" >/dev/null 2>&1; then up=1; break; fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$up" = 1 ] || { echo "FAIL: server did not come up"; exit 1; }

fail() { echo "FAIL: $1"; exit 1; }
check() { echo "smoke: $1"; }

# NUL-free payload: bodies pass through String, a pre-existing limitation
(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom || true) | head -c 100000 > "$WORK/body"

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

echo "smoke: all checks passed"
