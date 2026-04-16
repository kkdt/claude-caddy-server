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
