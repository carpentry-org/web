# Changelog

## Unreleased

### Added

- **HEAD method support** (RFC 7231). HEAD requests automatically match GET
  routes and return the same headers (including `Content-Length`) but with an
  empty body. For `sendfile` responses, the file size is computed for
  `Content-Length` without transferring the file data.

- **ETag-based conditional responses for static files.** `Response.file` and
  `Response.sendfile` now compute an `ETag` header from the SHA-1 hash of
  the file contents. When a request includes an `If-None-Match` header that
  matches the response's `ETag`, the server returns `304 Not Modified`
  with no body, eliminating redundant file transfers.

- `SHA1.hex-digest` computes the SHA-1 digest of a byte array and returns
  it as a 40-character lowercase hex string.

- **WebSocket subprotocol negotiation** (RFC 6455 §4.2.2). `App.WSP` registers
  a WebSocket route with a list of supported subprotocols. During the upgrade
  handshake, the server selects the first client-requested protocol that appears
  in the route's list and includes `Sec-WebSocket-Protocol` in the 101 response.
  The negotiated protocol is available to handlers via `(WebSocket.protocol ws)`.
  `App.WS` is unchanged and does not negotiate subprotocols.

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

- **`web-finalize-response` preserves explicit Content-Length.** When a response
  already has a `Content-Length` header (e.g. HEAD responses), finalization no
  longer overrides it with the body length.

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
