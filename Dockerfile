FROM caddy:alpine

# curl  — Keycloak token requests in entrypoint.sh
# jq    — JSON parsing of Keycloak token response
RUN apk add --no-cache curl jq

COPY entrypoint.sh    /entrypoint.sh
COPY Caddyfile        /etc/caddy/Caddyfile

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
