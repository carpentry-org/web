# web

A web framework for Carp with routing, JSON integration, and concurrent
connection handling via kqueue/epoll.

## Installation

```clojure
(load "git@github.com:carpentry-org/web@0.1.0")
```

## Usage

Define handler functions and register them with `defserver`, which expands
into a `main` that builds an `App` and starts serving:

```clojure
(load "git@github.com:carpentry-org/web@0.1.0")

(defn hello [req params]
  (Response.text @"Hello, world!"))

(defn greet [req params]
  (let [name (Map.get params "name")]
    (Response.text (fmt "Hello, %s!" &name))))

(defserver "0.0.0.0" 8080
  (GET "/"             hello)
  (GET "/hello/:name"  greet))
```

If you would rather build the app yourself, the underlying `App.create`,
`App.GET`, and `App.serve` functions are public:

```clojure
(defn main []
  (let [app (-> (App.create)
                (App.GET @"/" hello)
                (App.GET @"/hello/:name" greet))]
    (App.serve &app "0.0.0.0" 8080)))
```

### Handlers

A handler is a function `(Fn [&Request &(Map String String)] Response)`. It
receives a reference to the parsed HTTP request and a map of path parameters
captured by `:name` segments in the route pattern.

### Routing

Routes are matched in registration order. Pattern segments starting with `:`
are wildcards that capture the corresponding path segment:

```clojure
(App.GET app @"/users/:id" get-user)
(App.POST app @"/users/:uid/posts" create-post)
```

Unmatched requests receive a `404 Not Found` response.

### Response helpers

```clojure
(Response.text @"plain text")
(Response.html @"<h1>hi</h1>")
(Response.json &json-value)
(Response.not-found)
(Response.bad-request)
(Response.redirect @"/other")
(Response.with-header resp @"X-Custom" @"value")
(Response.with-status resp 201 @"Created")
```

### JSON integration

The framework includes the [json](https://github.com/carpentry-org/json)
library. Use `Response.json` to send JSON responses:

```clojure
(defn api-handler [req params]
  (let [j (JSON.obj [(JSON.entry @"ok" (JSON.Bool true))])]
    (Response.json &j)))
```

### Static files

Serve a directory of files with `App.static-dir` or the `(static dir)`
form inside `defserver`:

```clojure
(defserver "0.0.0.0" 3000
  (GET "/api/health" health-check)
  (static "public"))
```

This registers a wildcard GET route as a fallback. Requests for `/` serve
`public/index.html`. Paths containing `..` segments return 404.

You can also serve individual files with `Response.file`:

```clojure
(defn download [req params]
  (Response.file "data/report.pdf"))
```

Content types are inferred from file extensions via `Response.content-type-for`.

### Concurrent connections

The server uses kqueue (macOS) or epoll (Linux) to handle multiple connections
concurrently in a single-threaded, non-blocking event loop. HTTP keep-alive is
supported. Large responses are drained across multiple writable events, so they
do not stall other connections.

## Testing

```
carp -x test/web.carp
```

<hr/>

Have fun!
