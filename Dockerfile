FROM caddy:alpine

# curl    — Keycloak token requests in entrypoint.sh
# jq      — JSON parsing of Keycloak token response
# openssl — self-signed certificate generation when no certs are provided
RUN apk add --no-cache curl jq openssl

COPY entrypoint.sh    /entrypoint.sh
COPY Caddyfile        /etc/caddy/Caddyfile

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
