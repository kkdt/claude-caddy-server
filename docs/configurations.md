# Configuration

## Environment Variables

Set these in `pod.yaml` under `spec.containers[].env`:

| Variable | Description | Example |
|----------|-------------|---------|
| `UPSTREAM_API_URL` | Remote API base URL | `https://api.example.com` |
| `UI_ORIGIN` | Local React UI origin for CORS | `http://localhost:3000` |
| `KEYCLOAK_URL` | Keycloak server base URL | `https://keycloak.example.com` |
| `KEYCLOAK_REALM` | Keycloak realm name | `myrealm` |
| `KEYCLOAK_CLIENT_ID` | Caddy's client ID in Keycloak | sourced from Secret |
| `KEYCLOAK_CLIENT_SECRET` | Caddy's client secret in Keycloak | sourced from Secret |

## Certificates

Certificate files are optional. At startup, `entrypoint.sh` checks `/certs` for the following
files:

| File | Purpose |
|------|---------|
| `/certs/client.crt` | Client certificate presented to upstream (mTLS) |
| `/certs/client.key` | Client private key |
| `/certs/ca.crt` | CA certificate used to verify the upstream server |

**If all three files are present**, they are used as-is.

**If any file is missing**, self-signed certificates are generated automatically at
`/tmp/caddy-certs` using OpenSSL and used for the session. A warning is logged at startup.
Self-signed certificates are suitable for local development only — the upstream API must be
configured to accept them or skip client certificate verification.

To provide real certificates, update the `hostPath` volume in `pod.yaml`:

```yaml
volumes:
- name: certs
hostPath:
path: /path/to/certs    # <-- update this
type: Directory
```

To rely entirely on auto-generated certificates, remove the `volumes` and `volumeMounts`
sections from `pod.yaml`.