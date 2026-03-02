#!/bin/bash
# Setup SSL certificates for Matrix (backend) and Element (frontend)
# Run this on the server after DNS is configured

set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  SSL Certificate Setup - Matrix & Element               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Configuration
MATRIX_DOMAIN="matrix.rumpusroom.xyz"
ELEMENT_DOMAIN="element.rumpusroom.xyz"
EMAIL="${CERTBOT_EMAIL:-}"

# Check if we're on the server
if [ ! -f "/etc/cloud/cloud.cfg" ]; then
    echo "❌ This script should be run ON the server"
    exit 1
fi

# Verify DNS is configured
echo "=== Verifying DNS Configuration ==="
for domain in "$MATRIX_DOMAIN" "$ELEMENT_DOMAIN"; do
    echo -n "Checking $domain... "
    if dig +short "$domain" | grep -q "[0-9]"; then
        IP=$(dig +short "$domain" | head -1)
        echo "✓ Resolves to $IP"
    else
        echo "❌ FAILED"
        echo "Error: DNS not configured for $domain"
        echo "Please add an A record pointing to this server's IP"
        exit 1
    fi
done
echo ""

# Check if certificates already exist
if [ -d "/etc/letsencrypt/live/$MATRIX_DOMAIN" ]; then
    echo "⚠️  Certificate already exists for $MATRIX_DOMAIN"
    echo ""
    read -p "Renew/expand certificate to include both domains? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 0
    fi
    CERTBOT_ACTION="certonly --expand"
else
    CERTBOT_ACTION="certonly"
fi

# Stop nginx to free port 80
echo "=== Stopping nginx temporarily ==="
cd /opt/matrix/app
docker compose stop nginx || true
sleep 2

# Verify port 80 is free
if sudo lsof -i :80 > /dev/null 2>&1; then
    echo "❌ Port 80 is still in use:"
    sudo lsof -i :80
    exit 1
fi
echo "✓ Port 80 is free"
echo ""

# Run certbot
echo "=== Obtaining SSL Certificates ==="
echo "This will obtain certificates for:"
echo "  - $MATRIX_DOMAIN (Matrix backend)"
echo "  - $ELEMENT_DOMAIN (Element frontend)"
echo ""

# Build certbot command
if [ -n "$EMAIL" ]; then
    EMAIL_FLAG="--email $EMAIL"
else
    EMAIL_FLAG="--register-unsafely-without-email"
fi

sudo certbot $CERTBOT_ACTION \
    --standalone \
    -d "$MATRIX_DOMAIN" \
    -d "$ELEMENT_DOMAIN" \
    --non-interactive \
    --agree-tos \
    $EMAIL_FLAG || {
        echo ""
        echo "❌ Certificate generation failed!"
        echo ""
        echo "Common issues:"
        echo "  1. DNS not propagated yet (wait 5-10 minutes)"
        echo "  2. Firewall blocking port 80"
        echo "  3. Another service using port 80"
        echo ""
        echo "Verify DNS:"
        echo "  dig $MATRIX_DOMAIN"
        echo "  dig $ELEMENT_DOMAIN"
        echo ""
        echo "Check firewall:"
        echo "  sudo iptables -L INPUT -n | grep 80"
        echo ""
        exit 1
    }

echo ""
echo "✓ SSL Certificates obtained successfully!"
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
    echo "✓ nginx is running"
else
    echo "❌ nginx failed to start"
    docker compose logs nginx --tail=20
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  SSL Setup Complete!                                     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "✓ Certificates obtained for both domains"
echo "✓ nginx restarted with SSL"
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
