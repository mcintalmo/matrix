#!/bin/bash
# Setup SSL certificates for Matrix (backend) and Element (frontend)
# Run this on the server after DNS is configured

set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  SSL Certificate Setup - Matrix & Element               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables if available
if [ -f "/opt/matrix/app/.env" ]; then
    # shellcheck disable=SC1091
    set -a && source "/opt/matrix/app/.env" && set +a
elif [ -f "$SCRIPT_DIR/../.env" ]; then
    # shellcheck disable=SC1091
    set -a && source "$SCRIPT_DIR/../.env" && set +a
fi

DOMAIN="${DOMAIN:-rumpusroom.xyz}"
MATRIX_FQDN="${MATRIX_FQDN:-matrix.$DOMAIN}"
ELEMENT_WEB_FQDN="${ELEMENT_WEB_FQDN:-element-web.$DOMAIN}"
ELEMENT_CALL_FQDN="${ELEMENT_CALL_FQDN:-element-call.$DOMAIN}"
CHAT_FQDN="${CHAT_FQDN:-chat.$DOMAIN}"
CALL_FQDN="${CALL_FQDN:-call.$DOMAIN}"
LIVEKIT_FQDN="${LIVEKIT_FQDN:-livekit.$DOMAIN}"
ELEMENT_LEGACY_FQDN="element.$DOMAIN"
EMAIL="${CERTBOT_EMAIL:-${GMAIL_ACCOUNT:-}}"

DOMAINS=(
    "$MATRIX_FQDN"
    "$DOMAIN"
    "$ELEMENT_WEB_FQDN"
    "$ELEMENT_CALL_FQDN"
    "$CHAT_FQDN"
    "$CALL_FQDN"
    "$LIVEKIT_FQDN"
    "$ELEMENT_LEGACY_FQDN"
)

# Check if we're on the server
if [ ! -f "/etc/cloud/cloud.cfg" ]; then
    echo "[ERROR] This script should be run ON the server"
    exit 1
fi

# Verify DNS is configured
echo "=== Verifying DNS Configuration ==="
RESOLVED_DOMAINS=()
for d in "${DOMAINS[@]}"; do
    echo -n "Checking $d... "
    if dig +short "$d" | grep -q "[0-9]"; then
        IP=$(dig +short "$d" | head -1)
        echo "[OK] Resolves to $IP"
        RESOLVED_DOMAINS+=("$d")
    else
        echo "[WARN] DNS not resolved yet for $d"
    fi
done
echo ""

if [ ${#RESOLVED_DOMAINS[@]} -eq 0 ]; then
    echo "[ERROR] No domains resolved to an IP address. Check DNS configuration."
    exit 1
fi

# Check if certificates already exist
if [ -d "/etc/letsencrypt/live/$MATRIX_FQDN" ]; then
    echo "[INFO] Certificate already exists for $MATRIX_FQDN"
    echo ""
    read -p "Renew/expand certificate to include all domains? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 0
    fi
    CERTBOT_ACTION=(certonly --expand)
else
    CERTBOT_ACTION=(certonly)
fi

# Stop nginx to free port 80
echo "=== Stopping nginx temporarily ==="
cd /opt/matrix/app
docker compose stop nginx || true
sleep 2

# Verify port 80 is free
if sudo lsof -i :80 > /dev/null 2>&1; then
    echo "[ERROR] Port 80 is still in use:"
    sudo lsof -i :80
    exit 1
fi
echo "[OK] Port 80 is free"
echo ""

# Run certbot
echo "=== Obtaining SSL Certificates ==="
echo "Domains to certify:"
for d in "${RESOLVED_DOMAINS[@]}"; do
    echo "  - $d"
done
echo ""

# Build certbot command
CERTBOT_DOMAIN_FLAGS=()
for d in "${RESOLVED_DOMAINS[@]}"; do
    CERTBOT_DOMAIN_FLAGS+=("-d" "$d")
done

EMAIL_FLAGS=()
if [ -n "$EMAIL" ]; then
    EMAIL_FLAGS=(--email "$EMAIL")
else
    EMAIL_FLAGS=(--register-unsafely-without-email)
fi

sudo certbot "${CERTBOT_ACTION[@]}" \
    --standalone \
    "${CERTBOT_DOMAIN_FLAGS[@]}" \
    --non-interactive \
    --agree-tos \
    "${EMAIL_FLAGS[@]}" || {
        echo ""
        echo "[ERROR] Certificate generation failed!"
        echo ""
        echo "Common issues:"
        echo "  1. DNS not propagated yet (wait 5-10 minutes)"
        echo "  2. Firewall blocking port 80"
        echo "  3. Another service using port 80"
        echo ""
        exit 1
    }

echo ""
echo "[OK] SSL Certificates obtained successfully!"
echo ""

# Show certificate details
sudo certbot certificates

# Update nginx config to use the certificate
echo ""
echo "=== Updating nginx configuration ==="

# The certificate is stored under the first domain (matrix.rumpusroom.xyz)
# and includes both domains as Subject Alternative Names (SANs)

echo "Certificate location:"
echo "  /etc/letsencrypt/live/$MATRIX_DOMAIN/fullchain.pem"
echo "  /etc/letsencrypt/live/$MATRIX_DOMAIN/privkey.pem"
echo ""

# Start nginx
echo "=== Starting nginx with SSL ==="
cd /opt/matrix/app
docker compose up -d nginx

sleep 3

# Verify nginx started
if docker compose ps nginx | grep -q "Up"; then
    echo "[OK] nginx is running"
else
    echo "[ERROR] nginx failed to start"
    docker compose logs nginx --tail=20
    exit 1
fi

echo ""
echo "=========================================================="
echo "  SSL Setup Complete!"
echo "=========================================================="
echo ""
echo "[OK] Certificates obtained for all domains"
echo "[OK] nginx restarted with SSL"
echo ""
echo "Test your deployment:"
echo "  Matrix Backend:  https://$MATRIX_DOMAIN"
echo "  Element Frontend: https://$ELEMENT_DOMAIN"
echo ""
echo "Certificate auto-renewal:"
echo "  Certbot will automatically renew certificates"
echo "  Verify: sudo certbot renew --dry-run"
echo ""
echo "Note: You'll need to restart nginx after renewal:"
echo "  sudo systemctl reload nginx  # or"
echo "  cd /opt/matrix/app && docker compose restart nginx"
echo ""
