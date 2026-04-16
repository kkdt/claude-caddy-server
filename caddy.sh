#!/bin/sh
# Usage: ./caddy.sh {build|deploy|status|logs|clean}
#
#   build   Build the caddy-proxy container image
#   deploy  Apply the secret and deploy the pod via podman kube play
#   status  Show pod and container status
#   logs [-f] [N]  Show container logs; -f to follow (default: all lines, no follow)
#   clean   Stop the pod, remove the image, and remove the secret

set -e

IMAGE="localhost/caddy-proxy:latest"
POD_NAME="caddy-proxy"
CONTAINER_NAME="caddy-proxy-caddy"
SECRET_NAME="keycloak-creds"
POD_MANIFEST="pod.yaml"
SECRET_MANIFEST="secret.yaml"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { printf '[caddy] %s\n' "$*"; }
error() { printf '[caddy] ERROR: %s\n' "$*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || error "'$1' is not installed or not in PATH."
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
cmd_build() {
  info "Building image ${IMAGE}..."
  podman build -t "$IMAGE" .
  info "Build complete."
}

cmd_deploy() {
  if podman pod exists "$POD_NAME" 2>/dev/null; then
    info "Pod '${POD_NAME}' already exists — tearing down before redeploy..."
    podman kube down "$POD_MANIFEST" 2>/dev/null || true
  fi

  if [ -f "$SECRET_MANIFEST" ]; then
    info "Applying secret from ${SECRET_MANIFEST}..."
    podman kube play "$SECRET_MANIFEST"
  else
    info "No ${SECRET_MANIFEST} found — skipping secret. (Copy secret.yaml.example to get started.)"
  fi

  info "Deploying pod from ${POD_MANIFEST}..."
  podman kube play "$POD_MANIFEST"
  info "Pod deployed. Caddy is available at http://localhost:8080"
}

cmd_status() {
  info "--- Pod ---"
  podman pod inspect "$POD_NAME" \
    --format "Name: {{.Name}}  Status: {{.State}}  Created: {{.Created}}" \
    2>/dev/null || info "Pod '${POD_NAME}' not found."

  info "--- Containers ---"
  podman ps --all \
    --filter "pod=$POD_NAME" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" \
    2>/dev/null || true

  info "--- Image ---"
  podman image inspect "$IMAGE" \
    --format "ID: {{.Id}}  Created: {{.Created}}  Size: {{.Size}}" \
    2>/dev/null || info "Image '${IMAGE}' not found."

  info "--- Secret ---"
  if podman secret inspect "$SECRET_NAME" >/dev/null 2>&1; then
    podman secret inspect "$SECRET_NAME" \
      --format "Name: {{.Spec.Name}}  Created: {{.CreatedAt}}"
  else
    info "Secret '${SECRET_NAME}' not found."
  fi
}

cmd_logs() {
  TAIL="all"
  FOLLOW=0

  shift  # drop the 'logs' argument
  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--follow) FOLLOW=1 ;;
      [0-9]*)      TAIL="$1" ;;
      *) error "Unknown logs option: $1. Usage: logs [-f] [N]" ;;
    esac
    shift
  done

  TAIL_ARGS=""
  [ "$TAIL" != "all" ] && TAIL_ARGS="--tail $TAIL"

  if [ "$FOLLOW" = "1" ]; then
    info "Following logs for ${CONTAINER_NAME} (lines: ${TAIL}) (Ctrl-C to stop)..."
    podman logs -f $TAIL_ARGS "$CONTAINER_NAME"
  else
    info "Showing logs for ${CONTAINER_NAME} (lines: ${TAIL})..."
    podman logs $TAIL_ARGS "$CONTAINER_NAME"
  fi
}

cmd_clean() {
  info "Tearing down pod..."
  podman kube down "$POD_MANIFEST" 2>/dev/null \
    || info "Pod not running or already removed."

  info "Removing image ${IMAGE}..."
  podman rmi "$IMAGE" 2>/dev/null \
    || info "Image not found or already removed."

  info "Removing secret ${SECRET_NAME}..."
  podman secret rm "$SECRET_NAME" 2>/dev/null \
    || info "Secret not found or already removed."

  info "Clean complete."
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
require podman

case "${1:-}" in
  build)  cmd_build  ;;
  deploy) cmd_deploy ;;
  status) cmd_status ;;
  logs)   cmd_logs "$@" ;;
  clean)  cmd_clean  ;;
  *)
    printf 'Usage: %s {build|deploy|status|logs|clean}\n' "$0"
    printf '\n'
    printf '  build   Build the caddy-proxy container image\n'
    printf '  deploy  Apply the secret and deploy the pod\n'
    printf '  status  Show pod, container, image, and secret status\n'
    printf '  logs [-f] [N]  Show container logs; -f to follow (default: all lines, no follow)\n'
    printf '  clean   Stop pod, remove image and secret\n'
    exit 1
    ;;
esac
