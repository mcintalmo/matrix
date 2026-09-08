#!/bin/bash
# Complete server-side setup orchestration for Matrix Synapse
# Run this script on the server after deploying files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Matrix Synapse - Complete Server Setup                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Verify we're on the server
if [ ! -f "/etc/cloud/cloud.cfg" ]; then
    echo "❌ This script should be run ON the server, not locally."
    echo "   Use scripts/deploy.sh to deploy files from your local machine."
    exit 1
fi

# Step 2: Verify prerequisite files exist
echo "=== Checking prerequisites ==="
REQUIRED_FILES=("docker-compose.yml" "nginx/nginx.conf" "element/config.json")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$APP_DIR/$file" ]; then
        echo "❌ Error: Required file not found: $file"
        echo "   Run scripts/deploy.sh from your local machine first."
        exit 1
    fi
    echo "✓ $file"
done
echo ""

# Step 3: Check if nginx is disabled
echo "=== Checking system nginx ==="
if systemctl is-active nginx >/dev/null 2>&1; then
    echo "⚠️  System nginx is running. Stopping it..."
    sudo systemctl stop nginx
    sudo systemctl disable nginx
    sudo systemctl mask nginx
    echo "✓ System nginx disabled"
else
    echo "✓ System nginx not running"
fi
echo ""

# Step 4: Initialize .env file
echo "=== Setting up environment configuration ==="
if [ ! -f "$APP_DIR/.env" ]; then
    echo "Generating .env file..."
    "$SCRIPT_DIR/init-env.sh"
else
    echo "✓ .env file already exists"
fi
echo ""

# Step 5: Setup Synapse data directory
echo "=== Setting up Synapse data directory ==="
"$SCRIPT_DIR/setup-synapse.sh"
echo ""

# Step 6: Start services (except nginx initially)
echo "=== Starting services ==="
cd "$APP_DIR"
echo "Starting postgres, synapse, element, and coturn..."
docker compose up -d postgres synapse element coturn

# Wait for services to be healthy
echo "Waiting for services to be healthy..."
sleep 10

# Check health
SERVICES=("postgres" "synapse" "element")
for service in "${SERVICES[@]}"; do
    if docker compose ps "$service" | grep -q "healthy"; then
        echo "✓ $service is healthy"
    else
        STATUS=$(docker compose ps "$service" --format "{{.Status}}")
        echo "⚠️  $service status: $STATUS"
    fi
done
echo ""

# Step 7: Setup SSL certificate
echo "=== SSL Certificate Setup ==="
DOMAIN=$(grep "SYNAPSE_SERVER_NAME" .env | cut -d'=' -f2)

echo "This deployment uses separated domains:"
echo "  Backend:  matrix.rumpusroom.xyz (Synapse API)"
echo "  Frontend: element.rumpusroom.xyz (Element Web UI)"
echo ""

if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    # Check if certificate covers both domains
    if sudo certbot certificates | grep -q "element.rumpusroom.xyz"; then
        echo "✓ SSL certificate exists and covers both domains"
    else
        echo "⚠️  Certificate exists but may not cover element domain"
        echo "Run ./scripts/setup-ssl.sh to expand certificate"
    fi
else
    echo "SSL certificate not found. Setting up certificates for both domains..."
    echo "Prerequisites:"
    echo "  - DNS A records configured:"
    echo "    matrix.rumpusroom.xyz  → $(curl -s https://api.ipify.org)"
    echo "    element.rumpusroom.xyz → $(curl -s https://api.ipify.org)"
    echo "  - Port 80 must be open in firewall"
    echo ""
    read -p "Run SSL setup now? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Use dedicated SSL setup script
        "$SCRIPT_DIR/setup-ssl.sh"
        SSL_SETUP_DONE=true
    else
        echo "Skipping SSL setup. Run manually later:"
        echo "  ./scripts/setup-ssl.sh"
        SSL_SETUP_DONE=false
    fi
fi
echo ""

# Step 8: Start nginx (if SSL was skipped or already existed)
if [ "$SSL_SETUP_DONE" != "true" ]; then
    echo "=== Starting nginx ==="
    docker compose up -d nginx
    sleep 3

    if docker compose ps nginx | grep -q "Up"; then
        echo "✓ nginx is running"
    else
        echo "❌ nginx failed to start. Check logs:"
        echo "   docker compose logs nginx"
        exit 1
    fi
    echo ""
fi

# Step 9: Verify deployment
echo "=== Verifying deployment ==="
docker compose ps
echo ""

# Test health endpoint
echo "Testing Synapse health endpoint..."
if curl -sf http://localhost:8008/health | grep -q "OK"; then
    echo "✓ Synapse health check passed"
else
    echo "⚠️  Synapse health check failed"
fi

# Test HTTPS
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    echo "Testing HTTPS..."
    if curl -sf -k -I "https://$DOMAIN" | grep -q "HTTP"; then
        echo "✓ HTTPS is working"
    else
        echo "⚠️  HTTPS test failed"
    fi
fi
echo ""

# Step 10: Display next steps
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Setup Complete!                                         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "✓ All services are running"
echo "✓ Configuration is complete"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "NEXT STEPS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Create your admin user:"
echo "   docker compose exec synapse register_new_matrix_user \\"
echo "     -c /data/homeserver.yaml http://localhost:8008"
echo ""
echo "2. Visit your Matrix server:"
echo "   https://$DOMAIN"
echo ""
echo "3. Check logs if needed:"
echo "   docker compose logs -f"
echo ""
echo "4. Verify federation (optional):"
echo "   curl https://federationtester.matrix.org/api/report?server_name=$DOMAIN"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
