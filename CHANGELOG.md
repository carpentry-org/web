# Changelog

## Unreleased

### Changed
- `http` bumped to 0.5.0. A `multipart/form-data` part with no header block is
  now rejected by `Form.decode-multipart` instead of decoding to a nameless
  part with an empty body, and the whole body fails with it.

### Fixed
- **An `If-Modified-Since` in either obsolete date format is understood.** A
  client sending `Sunday, 06-Nov-94 08:49:37 GMT` or `Sun Nov  6 08:49:37 1994`
  had its conditional request thrown away and got the whole body back instead
  of a `304`. A malformed date is now rejected rather than shifted onto a real
  instant: `31 Feb 1994` used to parse as 3 March.

## [0.10.0]

### Added
- **Server-Sent Events.** `(SSE "/path" handler)` in `defserver`, or
  `App.SSE`, answers a GET with a `text/event-stream` response that stays
  open. The handler is called with `Connect` when a client subscribes, with
  `Tick` every `App.sse-tick-interval` seconds, and with `Close` when the
  client goes away; it queues events on the stream handle with
  `SSEStream.send` and `SSEStream.send-event`. A reconnecting client's
  `Last-Event-ID` is handed to the handler. Idle streams are not closed by
  the HTTP timeouts, and a tick that queues nothing sends a comment line so
  proxies keep the stream open. The `SSE` module encodes the wire format on
  its own for handlers that need an `id`, a `retry` time, or a comment.

### Changed
- **Registering WebSocket or Server-Sent Events routes no longer slows down
  ordinary requests.** An app with both kinds of route re-read and re-parsed
  the whole request buffer three times before answering a plain GET; it now
  reads and parses each request once.

### Fixed
- **A `304 Not Modified` no longer claims the cached resource is empty.** A
  conditional `GET` or `HEAD` that hit the cache went out with
  `Content-Length: 0`, so a client that trusted it learned the representation
  it already held was zero bytes long. A `304`, a `204 No Content` and a `1xx`
  now carry no `Content-Length` at all, as RFC 9110 §8.6 and §15.4.5 ask; the
  connection is still reused, since those statuses end at the header block
  rather than at a length. A `HEAD` that is answered normally still reports the
  length its `GET` would have had.
- **A conditional request is matched the way `If-None-Match` is defined.** The
  header used to be compared as one whole string against the response's `ETag`,
  so `If-None-Match: *` never matched, a client holding several cached variants
  (`"a", "b"`) re-downloaded the full body every time, and a weak validator
  (`W/"x"`) never matched its strong spelling. All three now match, as RFC 9110
  §13.1.2 asks for. A matching `If-None-Match` on a method other than `GET` or
  `HEAD` is answered with `412 Precondition Failed` instead of a `304 Not
  Modified`, and `If-Modified-Since` is ignored on those methods. A response
  that is not a `2xx` ignores both headers, so a `404` stays a `404`. The
  `412`, like the `304`, keeps every header the response had built up — a
  `Set-Cookie` the handler issued, an `Access-Control-Allow-Origin` an
  after-hook added — and drops only the ones that described the body it no
  longer carries. A response `ETag` or `Last-Modified` is found whatever its
  capitalisation, the way the request headers are already read.
- **A file whose extension is uppercase gets its real content type.** A path
  ending in `.JPG`, `.PNG`, `.HTML` or any other spelling of a known extension
  that is not all lower case was served as `application/octet-stream`, so a
  browser offered `IMG_1234.JPG` as a download instead of showing it.
  Extensions now match case-insensitively, the way nginx and Apache do.
- **A WebSocket close frame is checked before it is answered.** A close
  payload holding a single byte, a status code an endpoint must never receive
  (0-999, 1004, 1005, 1006, 1012-2999, and anything above 4999), or a reason
  that is not valid UTF-8 was accepted silently; such a frame now fails the
  connection with 1002 or 1007. A well-formed close is answered with the
  client's own status code echoed back, as RFC 6455 §5.5.1 asks for, and a
  close carrying no payload is still answered with an empty close.
- **A `304 Not Modified` keeps the headers the `200` would have sent.** The
  revalidation response was built from an empty header map holding nothing but
  `ETag`, so `Cache-Control`, `Vary`, `Last-Modified`, `Expires` and the
  `Access-Control-*` headers a hook had added were thrown away: a browser
  revalidating a cross-origin resource got a 304 with no
  `Access-Control-Allow-Origin` and failed the CORS check, and a shared cache
  lost the `Vary: Origin` telling it to key the entry by origin. The 304 now
  carries everything the `200` did apart from the body and the headers that
  describe it.

## [0.9.3]

### Changed
- `http` bumped to 0.4.2.

## [0.9.2]

### Changed
- Dependencies bumped: `http` 0.4.1, `json` 0.6.0, `log` 0.2.0,
  `utf8.carp` 0.2.0, and `orm` 0.5.1 in the todo example.

### Fixed
- **A `Range` header, a `Content-Type` header, a form body, or a static path
  whose byte length ran past its character count no longer kills the server.**
  One such request aborted the whole process. Every string `web` matches
  itself measures and slices in bytes now. The one remaining upstream path
  (a hostile `multipart/form-data` boundary parameter aborting while `http`
  parsed the media type) is fixed by the `http` 0.4.1 bump above.
- **A file extension is recognised on a non-ASCII path**, so such a file is
  served with its real `Content-Type` rather than
  `application/octet-stream`, and a non-ASCII directory path finds its index
  file.
- **`Response.json` no longer rounds numbers to six significant digits.** A
  database rowid of `1234567890` went out as `1.23457e+09`, `1000000` as
  `1e+06` and `3.141592653589793` as `3.14159`; each of those is now written
  in full. Numbers that already fitted in six digits, such as `42` and
  `3.14`, are unchanged.
- **`Response.json` no longer drops the character after an escape.** A string
  value or object key containing `"` or `\`, or a control character such as a
  newline or a tab, lost whatever code point came next if that code point was
  one of a large set including Greek, Cyrillic, `©`, `°`, `µ` and `»`: a body
  built from `"\nα"` was serialised as `"\n"`. Bytes that are not valid UTF-8
  were dropped or replaced too, and now reach the client untouched.

### Changed
- **`json` is pinned to 0.6.0 and `utf8.carp` to 0.2.0.** The `json` release
  drops its own, older copy of `utf8.carp`, so only one version of that module
  is compiled into a server now. `JSON` also gains RFC 6901 pointers, RFC 6902
  patch, RFC 7386 merge patch and a parser recursion limit, all of which are
  available to handlers.
- **`Range` request headers follow RFC 9110 §14.1.** The range unit is matched
  case-insensitively, whitespace and empty elements in the range-set are
  ignored, and a request for several ranges is answered with a `206` carrying
  the first satisfiable one instead of the whole representation.
- **`http` is pinned to 0.4.0.**

## 0.9.1 (2026-08-12)

### Changed
- **`file` is pinned to 0.3.0.** Its read path is all-or-nothing now, and
  `read-all` reports an error for an input whose length it cannot determine
  instead of reading into a buffer sized from a failed `ftell`. The static
  file server calls `read-all`, so a path that resolves to a pipe or a
  device is a clean `404` rather than a corrupted response.

### Fixed
- **The bundled todo example compiles again.** `examples/todo/server.carp` had
  not built since 0.6.0: it pinned long-superseded `web` and `orm` releases, and
  `Item.insert` now yields a `Long` rowid where the example still expected an
  `Int`. Its `id` is a `Long` now, it loads the repository's own `web.carp` the
  way the other bundled servers do, and a failing insert, update, or delete
  comes back as a `500` with the database's message instead of being silently
  discarded. `test/smoke.sh` compiles the example, so it cannot rot unnoticed
  again.

## 0.9.0 (2026-07-25)

### Changed
- **`Form.decode-multipart` / `decode-multipart-request` return
  `(Result (Array FormPart) String)`** and delegate to http's multipart
  parser instead of shipping a second one.
- **`FormPart.content-type` is now a `(Maybe String)`**, `Nothing` when the
  part carries no `Content-Type` header (previously `text/plain`).

### Added
- **HTTP date headers.** Every response now carries a `Date` header (an RFC 9110
  MUST for an origin server), and static-file responses add a `Last-Modified`
  header from the file's modification time, so caches and conditional requests
  have the freshness metadata they need.
- **`If-Modified-Since` conditional requests.** A static-file request whose
  `If-Modified-Since` is not older than the resource's modification time gets a
  `304 Not Modified`; an older or malformed value serves the full `200`.
  `If-None-Match` still takes precedence when both are present.
- **HTTP `Range` requests on static files.** The static-file server answers a
  single byte range (`bytes=A-B`, `bytes=A-`, `bytes=-N`) with `206 Partial
  Content` and a `Content-Range` header, seeking directly via `sendfile(2)`, so
  clients can resume interrupted downloads and seek within large assets. An
  unsatisfiable range gets `416 Range Not Satisfiable`; every static response
  now advertises `Accept-Ranges: bytes`. Multiple ranges and malformed specs
  fall back to the full `200`.
- **`App.request-timeout` (60s)** bounds first byte to complete request, so a
  slow-dripping body can no longer hold a connection open.
- **`Expect: 100-continue` is answered** with the interim response once the
  headers are complete.
- **An end-to-end smoke test** (`test/smoke.sh`, in CI) drives a real server
  with curl: large, chunked, and 100-continue uploads, keep-alive, 400s.

### Fixed
- **`SHA1` is correct on platforms where Carp's `Long` is 32-bit.** Every
  digest came out wrong there, so the WebSocket opening handshake failed
  (`Sec-WebSocket-Accept` is a SHA1 hash), and `HMAC-SHA1` and signed cookies
  were wrong too. 64-bit-`Long` platforms — including the macOS CI — were
  unaffected, which is why it went unnoticed.
- **Handlers no longer receive truncated request bodies.** The server
  dispatched at the end of the headers, so any body not in the same 4KB read
  arrived cut short, and the leftover bytes were misread as a second request.
  It now waits for the whole body (`Content-Length`, or the terminating
  chunk) and answers `400` for ambiguous framing (RFC 7230 §3.3.3).
- **Chunked bodies reach handlers decoded and normalized**: body dechunked,
  `Transfer-Encoding` removed, `Content-Length` set, trailers discarded.
- **`Connection: close` is honoured whatever its case, and alongside other
  connection options.** The field value was compared verbatim against
  `close`, so a client sending `CLOSE`, `Close`, or `close, TE` kept the
  socket open and got `Connection: keep-alive` back. The value is now read as
  a list of case-insensitive comma-separated tokens (RFC 9110 §7.6.1).
- **`Connection: close` is honoured when it arrives on its own header line.**
  A client sending `Connection: keep-alive` and `Connection: close` as two
  separate field lines kept the socket open, because only the first line was
  read. Every `Connection` line is now considered — whatever the case of its
  field name, so `connection:` from an HTTP/2 downgrading proxy counts too —
  as RFC 9110 §5.3 requires of repeated field lines.

## 0.8.0 (2026-07-12)

### Changed
- **`WebSocket.send-now` / `send-binary-now` now return a `Bool`.** `true`
  means the whole frame was written; `false` means the connection is dead or
  the client stopped draining, and the handler should stop sending. Callers
  that discarded the old `()` result need an `ignore`.

### Fixed
- **`send-now` no longer tears frames under backpressure.** Connection
  sockets are non-blocking, so when the kernel send buffer filled mid-frame,
  the old write loop dropped the rest of the frame (and silently discarded
  whole frames). The remainder desynchronized the client's WebSocket parser:
  later frames (including server pings) were swallowed as payload bytes of
  the incomplete frame, the client could never answer a ping again, and the
  server eventually closed the connection as dead. The write loop now polls
  for writability on `EAGAIN` and resumes (bounded by a 30s stall timeout),
  retries on `EINTR`, and suppresses `SIGPIPE` (`MSG_NOSIGNAL`/
  `SO_NOSIGPIPE`), so a streaming handler gets natural backpressure and a
  frame on the wire is always complete.
- **WebSocket text frames with invalid UTF-8 now close with 1007.** Per
  RFC 6455 §8.1, incoming text payloads (and reassembled fragmented text
  messages) are validated as UTF-8; malformed data fails the connection
  with close code 1007 instead of being passed to the handler.
- **WebSocket control frames are now fully validated per RFC 6455 §5.2/§5.5.**
  A control frame that is fragmented (FIN=0), carries more than 125 payload
  bytes, or uses a reserved opcode (0xB–0xF) fails the connection with close
  code 1002. The 0.6.0 "unknown opcodes close 1002" change reached the reserved
  data opcodes (0x3–0x7) but not the control range: the ping/pong/close fast
  path (opcode ≥ 8) still silently consumed 0xB–0xF. The FIN and payload-size
  checks are new.

## 0.7.0 (2026-07-06)

### Added

- **Cookie module.** Request-side helpers for reading cookies by name:
  `Request.cookies-map` returns all cookies as a `Map String String`,
  `Request.cookie` looks up a single cookie value.

- **Cookie signing with HMAC-SHA1.** `Cookie.set-secret` configures a
  signing key; `Cookie.sign` and `Cookie.verify` produce and validate
  `value.signature` tokens. `Request.signed-cookie` combines lookup and
  verification. A top-level `cookie-secret` function provides clean
  `defserver` integration.

- **`Response.set-cookie-with-max-age`.** Adds a `Set-Cookie` header
  with a `Max-Age` attribute (in seconds), complementing the existing
  `set-cookie` which uses the `http` library's `Expires`-only format.

- **`Response.clear-cookie`.** Expires a cookie by name, setting
  `Max-Age=0` and an empty value.

- **HMAC-SHA1 module** (`HMAC.sha1`, `HMAC.sha1-hex`) implementing
  RFC 2104 on top of the existing SHA-1 module, for cookie signing.

### Changed

- **`Response.chunked` uses StringBuf for O(n) chunk encoding.** Previously
  each loop iteration allocated a new string via `String.append`, making
  chunked encoding quadratic in the number of chunks. Now uses `StringBuf`
  for amortized O(1) appends.

### Fixed
- **Configurable CORS middleware.** `CORS.setup` configures origin,
  methods, headers, and max-age. `CORS.set-credentials!` and
  `CORS.set-expose-headers!` control additional headers. A `(cors ...)`
  form in `defserver` registers both hooks automatically.

- **`StaticFile` module for serving static files.** `StaticFile.handler`
  and `StaticFile.mount` serve files from a directory with directory index
  support (index.html by default, configurable via `handler-with`), path
  traversal prevention, and zero-copy transfer via `Response.sendfile`.

## 0.6.0 (2026-06-24)

### Added

- **Multi-core serving via SO_REUSEPORT.** `App.serve-with-workers`
  forks `n` worker processes, each running its own event loop bound to
  the same port. The kernel distributes incoming connections across
  workers. Falls back to single-process `serve` when `n` is 1 or less.
  `defserver` gains a `(workers N)` form for declarative configuration.

- **WebSocket fragment timeout and size limits.** Fragment accumulation
  now tracks per-connection timestamps via `ConnState.ws-frag-start`.
  `sweep-idle` closes connections where fragments have been accumulating
  longer than `App.ws-frag-ttl` seconds (default 30), preventing
  memory exhaustion from incomplete messages. A separate
  `App.ws-max-frag-size` constant (default 1 MiB) governs the maximum
  accumulated fragment size, independent of `App.max-request-size`.

- **Slow-client timeout (slow loris protection).** New connections must
  complete HTTP headers within `App.header-timeout` seconds (default 15).
  Connections that trickle bytes without completing the request line and
  headers are closed, regardless of how frequently data arrives. The
  per-request timer is tracked via `ConnState.read-start` and checked in
  `sweep-idle`. Keep-alive connections reset the timer between requests.

- **Request line validation.** Before full parsing, the server validates
  that the HTTP method is a recognized token (GET, HEAD, POST, PUT,
  DELETE, PATCH, OPTIONS, TRACE, CONNECT), that the version is HTTP/1.0
  or HTTP/1.1, and that the request line fits within `App.max-header-line`
  bytes (default 8192). Malformed requests receive an immediate 400 Bad
  Request response. `web-valid-method?` and `web-validate-request-line`
  are available as public helpers.

- **HEAD method support** (RFC 7231). HEAD requests automatically match GET
  routes and return the same headers (including `Content-Length`) but with an
  empty body. For `sendfile` responses, the file size is computed for
  `Content-Length` without transferring the file data.

- **ETag-based conditional responses for static files.** `Response.file`
  computes an `ETag` from the SHA-1 hash of the file contents.
  `Response.sendfile` computes an `ETag` from the file's modification time
  and size, preserving its zero-copy design by avoiding a full file read.
  When a request includes an `If-None-Match` header that matches the
  response's `ETag`, the server returns `304 Not Modified` with no body,
  eliminating redundant file transfers.

- `SHA1.hex-digest` computes the SHA-1 digest of a byte array and returns
  it as a 40-character lowercase hex string.

- **WebSocket subprotocol negotiation** (RFC 6455 §4.2.2). `App.WSP` registers
  a WebSocket route with a list of supported subprotocols. During the upgrade
  handshake, the server selects the first client-requested protocol that appears
  in the route's list and includes `Sec-WebSocket-Protocol` in the 101 response.
  The negotiated protocol is available to handlers via `(WebSocket.protocol ws)`.
  `App.WS` is unchanged and does not negotiate subprotocols.

### Fixed

- **WebSocket `decode-frame` 64-bit payload length truncation.**
  `decode-frame` silently ignored the high 4 bytes (offsets 2–5) of
  64-bit extended payload lengths (RFC 6455 §5.2), reading only the low
  32 bits. A remote peer sending a frame header with non-zero high bytes
  would cause the decoder to compute a wrong payload length, potentially
  desynchronizing the frame parser. The decoder now checks the high bytes
  and rejects frames whose payload length exceeds 32-bit `Int` range.

- **`Response.chunked` hardcoded status text.** `Response.chunked` always
  set the reason phrase to `"OK"` regardless of the status code passed.
  A `(Response.chunked 404 ...)` would produce `HTTP/1.1 404 OK` on the
  wire. Now uses `Status.reason` from the http library to derive the
  correct phrase.

- **WebSocket RFC 6455 protocol compliance.**
  - Protocol error paths (unexpected fragments, unknown opcodes) now send
    a 1002 close frame before disconnecting, as required by RFC 6455 §7.2.
  - Unknown opcodes (3–7, 11–15) trigger a 1002 protocol error close
    instead of being silently skipped (RFC 6455 §5.2).
  - Upgrade header matching is now case-insensitive for both the header
    name and value, per RFC 7230 §3.2 and RFC 6455 §4.2.1.
  - Oversized WebSocket messages now send a 1009 (Message Too Big) close
    frame before disconnecting, as required by RFC 6455 §7.4.1.
    Previously, the three size-limit code paths (single frame too large,
    first fragment too large, accumulated fragments too large) closed the
    connection silently without a close frame.

- **`web-finalize-response` preserves explicit Content-Length.** When a response
  already has a `Content-Length` header (e.g. HEAD responses), finalization no
  longer overrides it with the body length.

### Changed

- `WSRoute` gains a `protocols` field (`(Array String)`) listing supported
  subprotocols. Existing `App.WS` calls pass an empty array for backward
  compatibility.
- `WebSocket` gains a `protocol` field (`(Maybe String)`) holding the
  negotiated subprotocol, or `Nothing` if none was negotiated.
- `ConnState` gains a `ws-protocol` map for tracking the negotiated
  subprotocol per WebSocket connection.
- `web-try-ws-upgrade` return type gains a `(Maybe String)` for the
  negotiated protocol. `handle-ws-upgrade` includes `Sec-WebSocket-Protocol`
  in the 101 response when a protocol was negotiated.

## 0.5.0 (2026-06-02)

### Added

- **WebSocket server-initiated ping with dead client detection.**
  `WebSocket.encode-ping` encodes a ping frame. The server automatically sends
  ping frames to idle WebSocket connections (after `App.ws-ping-interval`
  seconds, default 30) and closes connections that miss
  `App.ws-max-missed-pongs` consecutive pongs (default 3). Pong responses from
  clients reset the counter. HTTP connections still use the simple idle timeout.
  Setting `ws-ping-interval` to 0 or negative disables pinging.
  `App.ws-ping-action` exposes the pure decision function for testing.

- **Multipart form-data parsing.** `FormPart` type represents a single part
  from a `multipart/form-data` request, with `name`, optional `filename`,
  `content-type`, and `body` fields. `Form.decode-multipart` parses a
  multipart body given a boundary string. `Form.decode-multipart-request`
  extracts the boundary from the Content-Type header and parses automatically.
  `Form.multipart?` checks whether a request has multipart content type.
  Header matching is case-insensitive.

- **Binary WebSocket frame support.** `WSEvent.Binary` variant for receiving
  binary frames (opcode 0x2). `WebSocket.encode-binary` encodes byte arrays
  as binary frames. `WebSocket.send-binary` and `WebSocket.send-binary-now`
  mirror their text counterparts for binary data.
- **WebSocket message fragmentation reassembly** (RFC 6455 §5.4). The server
  now checks the FIN bit, accumulates continuation frames (opcode 0) in a
  per-connection buffer, and dispatches the complete message once the final
  fragment arrives. Interleaved control frames (ping, pong, close) are
  processed immediately during fragmentation. Protocol violations (e.g.
  continuation without a start frame) close the connection.

- **WebSocket RFC 6455 compliance checks.** The server now validates reserved
  bits (RSV1-3) on incoming frames and closes the connection with status 1002
  if any are set (§5.2). Unmasked client frames are rejected with status 1002
  (§5.1). The upgrade handshake validates `Sec-WebSocket-Version: 13` and
  responds with 426 Upgrade Required if the version is missing or wrong (§4.2.1).

### Fixed

- **Content-Length no longer sent with chunked encoding.** `web-finalize-response`
  now skips the `Content-Length` header when `Transfer-Encoding` is already set,
  fixing an RFC 7230 §3.3.2 violation.
- **`log-after` no longer crashes when `_start` is missing.** The after-hook used
  `Maybe.unsafe-from` on the parsed start time, which panicked if `log-before`
  was not registered. Now falls back to `0l`.
- **File descriptor leak on `fstat` failure.** When `sendfile` opened a file but
  `fstat` failed, the fd was stored in `ConnState` but never closed. The fd is
  now closed immediately on `fstat` failure.

### Changed

- `ConnState` gains `ws-ping-count` and `ws-last-ping` maps for tracking
  server-initiated ping state per WebSocket connection.
- `sweep-idle` now takes a `poll` parameter and sends ping frames to idle
  WebSocket connections instead of closing them immediately.
- `WSFrame` gains `rsv` (`Int`) and `masked` (`Bool`) fields in addition to
  the existing `fin` field.
- `WSFrame` gains a `fin` field (`Bool`) for the FIN bit.
- `ConnState` gains `ws-frag-bufs` and `ws-frag-opcodes` maps for tracking
  in-progress fragmented messages per connection.

## 0.4.0 (2026-04-15)

### Added

- **WebSocket support** (#11). RFC 6455 upgrade handshake, text frames,
  ping/pong, and close frames over the existing non-blocking event loop.
  - `(WS "/path" handler)` in `defserver` registers a WebSocket route.
  - `WSEvent` sumtype: `Connect`, `(Message String)`, `Close`. Handlers
    receive one event at a time with path params and a `WebSocket` handle.
  - `WebSocket.send` queues outgoing text frames; the event loop drains
    the outbox after the handler returns.
  - `WebSocket.send-now` writes a frame directly to the socket,
    bypassing the outbox. For handlers that block (e.g. LLM token
    streaming) so each message reaches the client immediately.
  - Frame codec: `WebSocket.encode-text`, `encode-pong`, `encode-close`,
    `decode-frame`. Supports 7-bit, 16-bit, and 64-bit payload lengths.
  - Max frame size enforcement: frames exceeding `App.max-request-size`
    close the connection.
- **SHA-1** (`SHA1.digest`) in pure Carp (~75 lines, Long-based 32-bit
  ops). Used only for the WebSocket handshake, not for security.
- **Base64** (`Base64.encode`) in pure Carp. No external dependency.
- **Coverage harness** (`test/cov.carp`) using `Coverage.carp` from core.

### Changed

- `App` type gains a `ws-routes` field (`(Array WSRoute)`).
- `ConnState` gains `ws-route-idx` and `ws-params` maps for tracking
  active WebSocket connections.
- `conn-done-writing` skips clearing the read buffer for WebSocket
  connections so partial frames survive across write cycles.
- `conn-cleanup` removes WebSocket state on disconnect.
- `handle-readable` checks for WebSocket upgrade before HTTP routing,
  and dispatches active WebSocket connections to `handle-ws-readable`.
  The upgrade check parses the request once and passes the result through
  to avoid a double parse.
- `defserver` recognizes `(WS pattern handler)` forms.
- Extracted `web-routable-path` helper (was inlined 3 times).
- Extracted `ws-flatten-outbox` helper (was inlined 2 times).
- `.gitignore` now excludes gcov artifacts.

## 0.3.0 (2026-04-14)

### Added

- **Form body parsing** (#4). `Form.decode` decodes
  `application/x-www-form-urlencoded` bodies into `(Map String String)`,
  handling `+` as space and percent-encoding. `Form.decode-request` checks
  the Content-Type header first.
- **sendfile()** (#9). `Response.sendfile` serves files via `sendfile(2)`
  (zero-copy kernel-to-socket transfer). `App.static-dir` uses it
  automatically. Requires `IO.Raw.open` and `IO.Raw.fstat-size` from the
  Carp core.
- **Chunked responses** (#6). `Response.chunked` encodes an array of
  chunks with `Transfer-Encoding: chunked` framing.
- **`ConnState` deftype** for per-connection state. Passed by reference to
  named helper functions (`handle-accept`, `handle-writable`,
  `handle-readable`, `conn-cleanup`, `sweep-idle`, `flush-closed`).
  Thread-safe: each `serve` call creates its own state.

### Changed

- Refactored event loop from a monolithic function into named helpers
  operating on `&ConnState`. The serve function's main loop is now ~30 lines.
- Bumped `socket` dependency to 0.1.4 (sendfile-chunk).
- Static file serving (`App.static-dir`) now uses `sendfile(2)` instead of
  reading files into memory.
- File operations moved from socket library to Carp core (`IO.Raw.open`,
  `IO.Raw.close-fd`, `IO.Raw.fstat-size`, `IO.Raw.fileno`).

## 0.2.0 (2026-04-13)

### Added

- **Middleware** via `before` and `after` hooks (#1). Before-hooks run
  before route dispatch and can short-circuit with an early response.
  After-hooks run after the handler and can modify the response. Both
  receive the params map, so hooks can annotate it for downstream use.
  Use `(before fn)` and `(after fn)` in `defserver`.
- **CORS middleware** (#2). `CORS.before-hook` handles OPTIONS preflight,
  `CORS.after-hook` adds `Access-Control-Allow-Origin`. Configure with
  `CORS.configure`.
- **Cookie response helpers** (#3). `Response.set-cookie` takes a full
  `Cookie` value. `Response.set-simple-cookie` takes a name and value
  with sensible defaults (Path=/, HttpOnly, SameSite=Lax).
- **Prefix glob routes** (#5). A `*` as the last segment of a pattern
  captures the remaining path. `/api/*` matches `/api/foo/bar` with
  `* = foo/bar`. Works with named captures: `/users/:id/*`.
- **Request logging middleware** (#7). `log-before`/`log-after` print
  method, path, status code, and response time. Uses the `log` package,
  so any backend (simplelog, filelog, custom) works.
- **Custom error pages** (#12). `App.set-error` (or `(errors fn)` in
  `defserver`) registers a handler `(Fn [&Request Int String] Response)`
  that replaces the default plain-text error responses.
- **Form body parsing** (#4). `Form.decode` decodes
  `application/x-www-form-urlencoded` bodies into `(Map String String)`,
  handling `+` as space and percent-encoding. `Form.decode-request` checks
  the Content-Type header first.
- **sendfile()** (#9). `Response.sendfile` serves files via `sendfile(2)`
  (zero-copy kernel-to-socket transfer). `App.static-dir` uses it
  automatically.
- **Chunked responses** (#6). `Response.chunked` encodes an array of
  chunks with `Transfer-Encoding: chunked` framing.

### Changed

- `App.serve` now takes `before-hooks` and `after-hooks` arrays as extra
  parameters (between `app` and `host`). Pass empty arrays if you have no
  middleware.
- `defserver` recognizes `(before fn)`, `(after fn)`, `(errors fn)` forms
  alongside route forms.
- Added `log@0.1.1` dependency.
- Bumped `socket` dependency to 0.1.4 (sendfile, open-file, file-size).
- **Refactored event loop.** Per-connection state moved to module globals,
  event handlers extracted into `handle-accept`, `handle-writable`,
  `handle-readable`, `conn-cleanup`, `sweep-idle`, `flush-closed`.

## 0.1.0 (2026-04-12)

Initial release.

- Routing with named captures (`:param` segments) and wildcard (`*`) pattern.
- `defserver` macro for concise server definitions.
- Response helpers: `text`, `html`, `json`, `file`, `not-found`, `bad-request`,
  `redirect`, `with-header`, `with-status`, `content-type-for`.
- Static file serving via `App.static-dir` / `(static dir)` with
  content-type detection and directory-traversal protection.
- Non-blocking kqueue/epoll event loop with HTTP keep-alive. Large
  responses drain across writable events without stalling other connections.
- URL decoding on request paths.
- Request body size limit (`App.max-request-size`, default 1 MiB).
- Idle connection timeout (`App.idle-timeout`, default 60s).
- Graceful shutdown on SIGINT/SIGTERM.
- JSON integration via `carpentry-org/json`.
- Dependencies: `http@0.1.3`, `socket@0.1.2`, `json@0.2.1`, `file@0.1.2`.
