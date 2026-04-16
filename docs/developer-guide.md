# Developer Guide

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
