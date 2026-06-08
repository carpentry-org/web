# Deployment

## TLS / HTTPS

`web` does not terminate TLS, and this is deliberate. The framework speaks
plaintext HTTP and expects to run behind a TLS-terminating reverse proxy or
load balancer.

The reasoning (see issues #9 and #25 for the full discussion): doing TLS
safely is a maintenance commitment, not a feature you add once. The crypto
itself lives in OpenSSL upstream, but a built-in integration would put the
binding layer on us (certificate validation, hostname verification, error
handling), which is exactly where real TLS vulnerabilities come from and
exactly the kind of silent-correctness bug that passes every happy-path test.
Terminating TLS at the edge hands that responsibility to software whose
maintainers track the CVEs.

For outbound HTTPS from Carp (a client talking to an HTTPS server), use the
[`tls`](https://github.com/carpentry-org/tls) or
[`http-client`](https://github.com/carpentry-org/http-client) libraries
directly. The decision here is only about `web` accepting inbound TLS.

### nginx

Terminate TLS in nginx and proxy to `web` on a local plaintext port:

```nginx
server {
    listen 443 ssl;
    server_name example.com;

    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Redirect plaintext to HTTPS.
server {
    listen 80;
    server_name example.com;
    return 301 https://$host$request_uri;
}
```

WebSocket routes need the upgrade headers forwarded:

```nginx
    location /ws/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
```

### Caddy

Caddy provisions and renews certificates automatically:

```
example.com {
    reverse_proxy 127.0.0.1:3000
}
```

That single block handles ACME issuance, renewal, HTTPS redirects, and
WebSocket upgrades with no extra configuration.

### Reading the original request details

If your handler needs the client's real IP or the original scheme, configure
the proxy to send `X-Forwarded-For` / `X-Forwarded-Proto` (as shown in the
nginx block above) and read them from the request headers. `web` treats them
like any other header; it does not interpret them for you, so only trust them
when you control the proxy in front of the app.

### Binding

Bind `web` to a local address when it sits behind a proxy on the same host, so
the plaintext port is not exposed directly:

```carp
(defserver "127.0.0.1" 3000
  (GET "/" home))
```

Use `0.0.0.0` only when the proxy runs on a different host on a trusted
network.
