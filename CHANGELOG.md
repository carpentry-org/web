# Changelog

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
