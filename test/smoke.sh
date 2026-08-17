#!/usr/bin/env bash
# end-to-end smoke test: runs test/smoke-server.carp, drives it with curl, builds examples/todo
set -euo pipefail
cd "$(dirname "$0")/.."

PORT=8437
BASE="http://127.0.0.1:$PORT"
WORK=$(mktemp -d)
LOG=smoke-server.log

echo "smoke: compiling server"
carp -b test/smoke-server.carp

echo "smoke: compiling examples/todo/server.carp"
carp -b examples/todo/server.carp

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

# 11. a range-set is answered with its first satisfiable range
check "multi-range"
RH=$(curl -s --max-time 10 -D - -o "$WORK/multi" \
  -H 'Range: bytes=0-3, -2' "$BASE/static/index.html")
echo "$RH" | grep -qi 'Content-Range: bytes 0-3/11' || fail "multi-range Content-Range"
[ "$(cat "$WORK/multi")" = "root" ] || fail "multi-range body (got: $(cat "$WORK/multi"))"

# 12. headers whose byte length exceeds their character count are answered,
#     not aborted on
WIDE=$(printf '\303\244\303\244\303\244\303\244\303\244')
check "non-ASCII Range"
CODE=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
  -H "Range: $WIDE" "$BASE/static/index.html")
[ "$CODE" = "200" ] || fail "non-ASCII Range not served whole (got: $CODE)"

check "non-ASCII Content-Type"
BODY=$(curl -s --max-time 10 -H "Content-Type: $WIDE$WIDE$WIDE$WIDE" \
  --data-binary 'a=1' "$BASE/form")
[ "$BODY" = "none" ] || fail "non-ASCII Content-Type decoded a form (got: $BODY)"

check "server survived"
[ "$(curl -sf --max-time 10 "$BASE/ok")" = "ok" ] || fail "server died on a non-ASCII header"

# 13. a Server-Sent Events stream opens, pushes on connect, and keeps ticking.
#     curl is cut off by --max-time because the stream never ends.
check "SSE stream"
curl -s --max-time 5 --no-buffer -H 'Last-Event-ID: 77' \
  -D "$WORK/sse.head" -o "$WORK/sse.body" "$BASE/events" || true
grep -qi '^HTTP/1.1 200' "$WORK/sse.head" || fail "SSE stream not 200"
grep -qi '^content-type: text/event-stream' "$WORK/sse.head" \
  || fail "SSE stream has the wrong Content-Type"
grep -qi '^cache-control: no-cache' "$WORK/sse.head" || fail "SSE stream is cached"
if grep -qi '^content-length:' "$WORK/sse.head"; then
  fail "SSE stream head carries a Content-Length"
fi
grep -q '^event: ready$' "$WORK/sse.body" || fail "no connect event on the stream"
grep -q '^data: 77$' "$WORK/sse.body" || fail "Last-Event-ID did not reach the handler"
TICKS=$(grep -c '^data: tick$' "$WORK/sse.body" || true)
[ "${TICKS:-0}" -ge 2 ] || fail "stream stopped ticking (got $TICKS ticks)"

# 14. a tick that queues nothing sends a keep-alive comment instead
check "SSE keep-alive comment"
curl -s --max-time 5 --no-buffer -o "$WORK/quiet.body" "$BASE/quiet" || true
grep -q '^data: hi$' "$WORK/quiet.body" || fail "no connect event on the quiet stream"
KEEPS=$(grep -c '^:$' "$WORK/quiet.body" || true)
[ "${KEEPS:-0}" -ge 2 ] || fail "quiet stream sent no keep-alives (got $KEEPS)"

check "server survived the stream"
[ "$(curl -sf --max-time 10 "$BASE/ok")" = "ok" ] || fail "server died on an SSE stream"

echo "smoke: all checks passed"
