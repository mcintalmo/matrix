#!/usr/bin/env bash
# Certbot renewal deploy hook to reload Nginx in Docker
set -euo pipefail

NGINX_CONTAINER="$(docker ps --filter "name=nginx" --format "{{.Names}}" | head -n 1 || true)"

if [ -n "$NGINX_CONTAINER" ]; then
    echo "[INFO] Reloading Nginx in container: $NGINX_CONTAINER..."
    docker exec "$NGINX_CONTAINER" nginx -s reload
    echo "[OK] Nginx reloaded successfully after certificate renewal"
else
    echo "[WARN] No running Nginx container found to reload"
fi
