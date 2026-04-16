# caddy.sh

Management script for the caddy-proxy local development container. Wraps `podman` commands
for building, deploying, monitoring, and cleaning up the proxy.

## Requirements

- `podman` must be installed and available in `PATH`

## Usage

```
./caddy.sh {build|deploy|status|logs|clean}
./caddy.sh logs [-f] [N]
```

---

## Commands

### `build`

Builds the `caddy-proxy` container image from the `Dockerfile` in the current directory.

```sh
./caddy.sh build
```

- Tags the image as `localhost/caddy-proxy:latest`
- Must be run before `deploy` when the `Dockerfile`, `Caddyfile`, or `entrypoint.sh` change

---

### `deploy`

Deploys the pod using `podman kube play`.

```sh
./caddy.sh deploy
```

1. If `secret.yaml` exists, applies it first via `podman kube play secret.yaml`
2. Deploys the pod from `pod.yaml` via `podman kube play pod.yaml`
3. Caddy becomes available at `http://localhost:8080`

If `secret.yaml` is not present, the secret step is skipped with a warning. The pod will
still attempt to start, but Keycloak authentication will fail without valid credentials.

To create `secret.yaml`, copy the template and fill in base64-encoded values:

```sh
cp secret.yaml.example secret.yaml
echo -n "your-client-id"     | base64
echo -n "your-client-secret" | base64
```

---

### `status`

Displays a summary of all managed resources.

```sh
./caddy.sh status
```

Reports four sections:

| Section | Details shown |
|---------|---------------|
| Pod | Name, state, creation time |
| Containers | Name, status, ports (all containers in the pod) |
| Image | ID, creation time, size |
| Secret | Name, creation time |

Each section prints a not-found message instead of erroring if the resource does not exist.

Example output:

```
[caddy] --- Pod ---
[caddy] Name: caddy-proxy  Status: Running  Created: 2026-04-16T10:00:00Z
[caddy] --- Containers ---
NAMES                STATUS          PORTS
caddy-proxy-caddy    Up 2 minutes    0.0.0.0:8080->80/tcp
[caddy] --- Image ---
[caddy] ID: sha256:abc123...  Created: 2026-04-16T09:55:00Z  Size: 45MB
[caddy] --- Secret ---
[caddy] Name: keycloak-creds  Created: 2026-04-16T09:58:00Z
```

---

### `logs`

Shows log output from the Caddy container.

```sh
./caddy.sh logs [-f] [N]
```

| Option | Description |
|--------|-------------|
| _(none)_ | Print all log lines and exit |
| `N` | Print the last N lines and exit |
| `-f` | Follow log output in real time (Ctrl-C to stop) |
| `-f N` | Follow from the last N lines |

Examples:

```sh
./caddy.sh logs          # print all lines and exit
./caddy.sh logs 50       # print last 50 lines and exit
./caddy.sh logs -f       # follow all lines
./caddy.sh logs -f 50    # follow from last 50 lines
./caddy.sh logs 50 -f    # same — flag order does not matter
```

Caddy logs are emitted as JSON (configured in `Caddyfile`). Useful for:

- Confirming the Keycloak token was obtained at startup
- Watching proxied requests in real time
- Diagnosing mTLS or CORS errors

---

### `clean`

Stops and removes all resources created by `build` and `deploy`.

```sh
./caddy.sh clean
```

Removes in order:

1. **Pod** — `podman kube down pod.yaml`
2. **Image** — `podman rmi localhost/caddy-proxy:latest`
3. **Secret** — `podman secret rm keycloak-creds`

Each step is non-destructive: if a resource is already absent, a warning is printed and
the script continues. Safe to run multiple times.

---

## Typical Workflow

```sh
# First time setup
cp secret.yaml.example secret.yaml
# fill in base64-encoded client_id and client_secret in secret.yaml

# Build and deploy
./caddy.sh build
./caddy.sh deploy

# Check everything is running
./caddy.sh status

# Watch logs (follow mode)
./caddy.sh logs -f

# Tear everything down
./caddy.sh clean
```

## Rebuilding After a Config Change

```sh
./caddy.sh clean
./caddy.sh build
./caddy.sh deploy
```

---

## Resource Reference

| Resource | Name |
|----------|------|
| Image | `localhost/caddy-proxy:latest` |
| Pod | `caddy-proxy` |
| Container | `caddy-proxy-caddy` |
| Secret | `keycloak-creds` |
| Pod manifest | `pod.yaml` |
| Secret manifest | `secret.yaml` |
