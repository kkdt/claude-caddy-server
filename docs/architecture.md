# Architecture

## Overview 

```
React UI (localhost:3000)
        |
        v
Caddy Proxy (localhost:8080)
        |  - mTLS client certificate
        |  - Keycloak Bearer token (client_credentials)
        v
Remote API Services (https://api.example.com)
```

Caddy runs in a Podman container on the developer's machine. It intercepts all API calls from the
local React UI, attaches a Keycloak-issued Bearer token, and forwards requests to remote APIs over
mutual TLS.

---

## Files

| File | Description |
|------|-------------|
| `Caddyfile` | Caddy reverse proxy configuration |
| `Dockerfile` | Container image build (caddy:alpine + curl + jq) |
| `entrypoint.sh` | Token lifecycle management and Caddy startup |
| `pod.yaml` | `podman kube play` Pod manifest |
| `secret.yaml.example` | Template for Keycloak credentials Secret |

---

## How It Works

### Keycloak Token Flow

Caddy uses the OAuth2 **client_credentials** grant to authenticate with Keycloak as a service
account — no user login is involved.

1. `entrypoint.sh` calls the Keycloak token endpoint at startup:
    ```
    POST {KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/token
    grant_type=client_credentials
    client_id=...
    client_secret=...
    ```
2. The obtained Bearer token is written to `/tmp/caddy-token.conf` as a Caddy `header_up` directive.
3. Caddy imports this file inside its `reverse_proxy` block, injecting the token into every
   upstream request as `Authorization: Bearer <token>`.
4. Before the token expires, `entrypoint.sh` fetches a fresh token, updates
   `/tmp/caddy-token.conf`, and runs `caddy reload` — no downtime, no container restart.

### mTLS

Caddy presents a client certificate when establishing TLS connections to the upstream API, and
verifies the upstream server's certificate against a CA bundle. Certificate paths are resolved
by `entrypoint.sh` at startup and exported as `CLIENT_CERT_PATH`, `CLIENT_KEY_PATH`, and
`CA_CERT_PATH`, which the `Caddyfile` reads via environment variable placeholders.

If no certificates are mounted at `/certs`, `entrypoint.sh` generates a local CA and a
client certificate signed by it using OpenSSL. The generated files are ephemeral — they are
recreated on each container start.

### CORS

The React UI runs on a different port than the Caddy proxy (e.g., `localhost:3000` vs
`localhost:8080`). Browsers treat different ports as different origins and enforce CORS, blocking
requests unless the server explicitly permits them.

Caddy handles this in two steps:

1. **Preflight requests** — browsers send an `OPTIONS` request before any cross-origin call with
   custom headers. Caddy matches these with the `@cors_preflight` matcher and responds immediately
   with `204 No Content` and the required `Access-Control-*` headers, without forwarding to
   upstream.

2. **Actual requests** — Caddy injects `Access-Control-Allow-Origin` and
   `Access-Control-Allow-Credentials` headers on all non-preflight responses.

The allowed origin is set explicitly via the `UI_ORIGIN` environment variable rather than `*`.
This is required when requests include credentials — browsers reject `Access-Control-Allow-Origin: *`
combined with `Access-Control-Allow-Credentials: true`.