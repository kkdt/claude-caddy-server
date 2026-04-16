#!/bin/sh
# 1. Resolves mTLS certificates — uses /certs if provided, otherwise generates
#    self-signed certificates at /tmp/caddy-certs.
# 2. Fetches a Keycloak client_credentials token, writes it to /tmp/caddy-token.conf,
#    starts Caddy, then refreshes the token before it expires via caddy reload.

set -e

TOKEN_CONF="/tmp/caddy-token.conf"
PROVIDED_CERTS_DIR="/certs"
DEFAULT_CERTS_DIR="/tmp/caddy-certs"
CADDY_PID=""

# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------
cleanup() {
  echo "[entrypoint] Received shutdown signal. Stopping Caddy..."
  if [ -n "$CADDY_PID" ]; then
    kill -TERM "$CADDY_PID" 2>/dev/null || true
    wait "$CADDY_PID" 2>/dev/null || true
  fi
  exit 0
}
trap cleanup TERM INT

# ---------------------------------------------------------------------------
# Certificate resolution
# ---------------------------------------------------------------------------
resolve_certificates() {
  if [ -f "${PROVIDED_CERTS_DIR}/client.crt" ] && \
     [ -f "${PROVIDED_CERTS_DIR}/client.key" ] && \
     [ -f "${PROVIDED_CERTS_DIR}/ca.crt" ]; then
    echo "[entrypoint] Using provided certificates from ${PROVIDED_CERTS_DIR}."
    export CLIENT_CERT_PATH="${PROVIDED_CERTS_DIR}/client.crt"
    export CLIENT_KEY_PATH="${PROVIDED_CERTS_DIR}/client.key"
    export CA_CERT_PATH="${PROVIDED_CERTS_DIR}/ca.crt"
  else
    echo "[entrypoint] No certificates found at ${PROVIDED_CERTS_DIR}. Generating self-signed certificates..."
    mkdir -p "$DEFAULT_CERTS_DIR"

    # CA key and self-signed certificate
    openssl genrsa -out "${DEFAULT_CERTS_DIR}/ca.key" 2048 2>/dev/null
    openssl req -x509 -new -nodes \
      -key  "${DEFAULT_CERTS_DIR}/ca.key" \
      -sha256 -days 365 \
      -subj "/CN=caddy-local-ca" \
      -out  "${DEFAULT_CERTS_DIR}/ca.crt" 2>/dev/null

    # Client key and certificate signed by the local CA
    openssl genrsa -out "${DEFAULT_CERTS_DIR}/client.key" 2048 2>/dev/null
    openssl req -new \
      -key  "${DEFAULT_CERTS_DIR}/client.key" \
      -subj "/CN=caddy-client" \
      -out  "${DEFAULT_CERTS_DIR}/client.csr" 2>/dev/null
    openssl x509 -req \
      -in        "${DEFAULT_CERTS_DIR}/client.csr" \
      -CA        "${DEFAULT_CERTS_DIR}/ca.crt" \
      -CAkey     "${DEFAULT_CERTS_DIR}/ca.key" \
      -CAcreateserial \
      -out       "${DEFAULT_CERTS_DIR}/client.crt" \
      -days 365 -sha256 2>/dev/null

    export CLIENT_CERT_PATH="${DEFAULT_CERTS_DIR}/client.crt"
    export CLIENT_KEY_PATH="${DEFAULT_CERTS_DIR}/client.key"
    export CA_CERT_PATH="${DEFAULT_CERTS_DIR}/ca.crt"

    echo "[entrypoint] Self-signed certificates generated at ${DEFAULT_CERTS_DIR}."
    echo "[entrypoint] WARNING: Self-signed certificates are for local development only."
  fi
}

# ---------------------------------------------------------------------------
# Token helpers
# ---------------------------------------------------------------------------
fetch_token_response() {
  curl -sf \
    -X POST "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_id=${KEYCLOAK_CLIENT_ID}" \
    --data-urlencode "client_secret=${KEYCLOAK_CLIENT_SECRET}"
}

write_token_conf() {
  # Caddy imports this file inside the reverse_proxy block on each reload
  printf 'header_up Authorization "Bearer %s"\n' "$1" > "$TOKEN_CONF"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
resolve_certificates

echo "[entrypoint] Fetching initial Keycloak token from ${KEYCLOAK_URL} (realm: ${KEYCLOAK_REALM})..."

RESPONSE=$(fetch_token_response)
ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token // empty')
EXPIRES_IN=$(echo "$RESPONSE"  | jq -r '.expires_in  // 300')

if [ -z "$ACCESS_TOKEN" ]; then
  echo "[entrypoint] ERROR: Could not obtain Keycloak token."
  echo "[entrypoint] Response: $RESPONSE"
  exit 1
fi

# Refresh 30 seconds before the token expires
REFRESH_INTERVAL=$(( EXPIRES_IN - 30 ))
echo "[entrypoint] Token obtained (expires in ${EXPIRES_IN}s; will refresh in ${REFRESH_INTERVAL}s)."

write_token_conf "$ACCESS_TOKEN"

echo "[entrypoint] Starting Caddy..."
caddy run --config /etc/caddy/Caddyfile &
CADDY_PID=$!

# ---------------------------------------------------------------------------
# Token refresh loop — updates caddy-token.conf and triggers a graceful reload
# ---------------------------------------------------------------------------
while kill -0 "$CADDY_PID" 2>/dev/null; do
  sleep "$REFRESH_INTERVAL"

  echo "[entrypoint] Refreshing Keycloak token..."
  RESPONSE=$(fetch_token_response)
  ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token // empty')

  if [ -n "$ACCESS_TOKEN" ]; then
    write_token_conf "$ACCESS_TOKEN"
    caddy reload --config /etc/caddy/Caddyfile
    echo "[entrypoint] Token refreshed and Caddy reloaded."
  else
    echo "[entrypoint] WARNING: Token refresh failed; retrying in 30s."
    sleep 30
  fi
done

wait "$CADDY_PID"
