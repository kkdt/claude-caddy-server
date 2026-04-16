# claude-caddy

## Overview

This project provides configuration and deployment files for using [Caddy](https://caddyserver.com/docs/getting-started)
locally as a backend proxy server for UI development.

## Use Case

As a developer, I can run my React UI application on my laptop and configure it to hit APIs through the Caddy Server to
hit remote API services.

## Requirements

1. Utilize Caddy Docker container
2. Supports mTLS
3. Supports Keycloak single-sign-on; assume the Caddy Server has client credentials in Keycloak
4. Certificates will be provided into the Caddy Server
5. Do not use Docker Compose; Use `podman kube play` for deployment

---

## Architecture

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

## Configuration

### Environment Variables

Set these in `pod.yaml` under `spec.containers[].env`:

| Variable | Description | Example |
|----------|-------------|---------|
| `UPSTREAM_API_URL` | Remote API base URL | `https://api.example.com` |
| `UI_ORIGIN` | Local React UI origin for CORS | `http://localhost:3000` |
| `KEYCLOAK_URL` | Keycloak server base URL | `https://keycloak.example.com` |
| `KEYCLOAK_REALM` | Keycloak realm name | `myrealm` |
| `KEYCLOAK_CLIENT_ID` | Caddy's client ID in Keycloak | sourced from Secret |
| `KEYCLOAK_CLIENT_SECRET` | Caddy's client secret in Keycloak | sourced from Secret |

### Certificates

The following certificate files must be present on the host and mounted into the container at `/certs`:

| File | Purpose |
|------|---------|
| `/certs/client.crt` | Client certificate presented to upstream (mTLS) |
| `/certs/client.key` | Client private key |
| `/certs/ca.crt` | CA certificate used to verify the upstream server |

Update the `hostPath` volume in `pod.yaml` to point to the directory containing these files:

```yaml
volumes:
  - name: certs
    hostPath:
      path: /path/to/certs    # <-- update this
      type: Directory
```

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

Caddy presents `client.crt` / `client.key` when establishing TLS connections to the upstream API.
The upstream server's certificate is verified against `ca.crt`. This is configured in the
`transport http` block of the `Caddyfile`.

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

---

## Quickstart

### 1. Build the Image

```bash
podman build -t localhost/caddy-proxy:latest .
```

### 2. Create the Credentials Secret

```bash
cp secret.yaml.example secret.yaml
```

Base64-encode your Keycloak client credentials and update `secret.yaml`:

```bash
echo -n "your-client-id"     | base64
echo -n "your-client-secret" | base64
```

Apply the secret:

```bash
podman kube play secret.yaml
```

### 3. Configure `pod.yaml`

Update the following values in `pod.yaml`:

- `UPSTREAM_API_URL` — your remote API base URL
- `UI_ORIGIN` — your React UI origin (e.g., `http://localhost:3000`)
- `KEYCLOAK_URL` — your Keycloak server URL
- `KEYCLOAK_REALM` — your Keycloak realm
- `volumes[].hostPath.path` — path to your certificate directory

### 4. Deploy

```bash
podman kube play pod.yaml
```

Caddy is now available at `http://localhost:8080`. Point your React UI's API base URL to
`http://localhost:8080`.

### 5. Teardown

```bash
podman kube down pod.yaml
```

---

## Development Tips

**Validate the Caddyfile before deploying:**

```bash
podman run --rm -v $PWD/Caddyfile:/etc/caddy/Caddyfile caddy:alpine caddy validate --config /etc/caddy/Caddyfile
```

**Tail Caddy logs:**

```bash
podman logs -f caddy-proxy-caddy
```

**Manually reload Caddy config inside the container:**

```bash
podman exec caddy-proxy-caddy caddy reload --config /etc/caddy/Caddyfile
```

**Verify the token is being sent to upstream:**

```bash
# Temporary: enable debug logging in Caddyfile by changing level to DEBUG
podman logs -f caddy-proxy-caddy | grep Authorization
```
