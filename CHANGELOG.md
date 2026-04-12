# Changelog

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

### Changed

- `App.serve` now takes `before-hooks` and `after-hooks` arrays as extra
  parameters (between `app` and `host`). Pass empty arrays if you have no
  middleware.
- `defserver` recognizes `(before fn)`, `(after fn)`, `(errors fn)` forms
  alongside route forms.
- Added `log@0.1.1` dependency.

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
