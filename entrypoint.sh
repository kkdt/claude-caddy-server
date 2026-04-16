#!/bin/sh
# Fetches a Keycloak client_credentials token, writes it to /tmp/caddy-token.conf,
# starts Caddy, then refreshes the token before it expires via caddy reload.

set -e

TOKEN_CONF="/tmp/caddy-token.conf"
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
