# web

A web framework for Carp with routing, middleware, JSON integration, and
concurrent connection handling via kqueue/epoll.

## Installation

```clojure
(load "git@github.com:carpentry-org/web@0.2.0")
```

## Usage

Define handler functions and register them with `defserver`:

```clojure
(load "git@github.com:carpentry-org/web@0.2.0")

(defn hello [req params]
  (Response.text @"Hello, world!"))

(defn greet [req params]
  (let [name (Map.get params "name")]
    (Response.text (fmt "Hello, %s!" &name))))

(defserver "0.0.0.0" 8080
  (GET "/"             hello)
  (GET "/hello/:name"  greet))
```

### Handlers

A handler is `(Fn [&Request &(Map String String)] Response)`. It receives
the parsed HTTP request and a map of path parameters captured by `:name`
segments in the route pattern. Middleware before-hooks can add entries to
this map for downstream use.

### Routing

Routes are matched in registration order. Pattern segments starting with
`:` capture the corresponding path segment. A `*` as the last segment
captures the rest of the path:

```clojure
(GET "/users/:id"     get-user)
(GET "/api/*"         api-catch-all)  ; params has "*" = "the/rest"
(GET "/users/:id/*"   user-sub)       ; both :id and * captured
```

Unmatched requests go through the error handler.

### Middleware

Before-hooks run before route dispatch, after-hooks run after. Both
receive the params map, so hooks can annotate it for downstream use.

```clojure
(defn require-auth [req params]
  (if (has-token req)
    (Maybe.Nothing)                        ; continue
    (Maybe.Just (Response.text @"denied")))) ; short-circuit

(defn add-header [req params resp]
  (Response.with-header resp @"X-Server" @"carp"))

(defserver "0.0.0.0" 3000
  (before require-auth)
  (after add-header)
  (GET "/" hello))
```

### CORS

```clojure
(defserver "0.0.0.0" 3000
  (CORS.configure @"http://localhost:5173")
  (before CORS.before-hook)
  (after CORS.after-hook)
  (GET "/api/data" handler))
```

### Cookies

```clojure
(defn login [req params]
  (-> (Response.text @"logged in")
      (Response.set-simple-cookie @"session" @"abc123")))
```

`set-simple-cookie` uses `Path=/`, `HttpOnly`, `SameSite=Lax`. For full
control, use `Response.set-cookie` with a `Cookie` value from the `http`
library.

### Request logging

```clojure
(load "git@github.com:carpentry-org/simplelog@<version>")

(defserver "0.0.0.0" 3000
  (SimpleLog.install Log.INFO)
  (before log-before)
  (after log-after)
  (GET "/" hello))
```

Prints `GET /path 200 3ms` for each request. Works with any `log` backend
(simplelog, filelog, or your own).

### Response helpers

```clojure
(Response.text @"plain text")
(Response.html @"<h1>hi</h1>")
(Response.json &json-value)
(Response.file "path/to/file.pdf")
(Response.not-found)
(Response.bad-request)
(Response.redirect @"/other")
(Response.with-header resp @"X-Custom" @"value")
(Response.with-status resp 201 @"Created")
```

### Static files

```clojure
(defserver "0.0.0.0" 3000
  (GET "/api/health" health-check)
  (static "public"))
```

Serves `public/index.html` at `/`. Paths with `..` return 404. Content
types are inferred from file extensions.

### Custom error pages

```clojure
(defn my-errors [req code msg]
  (Response.html (fmt "<h1>%d %s</h1>" code &msg)))

(defserver "0.0.0.0" 3000
  (errors my-errors)
  (GET "/" hello))
```

The error handler receives the request, status code, and reason phrase.

### Concurrent connections

The server uses kqueue (macOS) or epoll (Linux) in a single-threaded,
non-blocking event loop. HTTP keep-alive is supported. Large responses
drain across multiple writable events without stalling other connections.

## Testing

```
carp -x test/web.carp
```

<hr/>

Have fun!
