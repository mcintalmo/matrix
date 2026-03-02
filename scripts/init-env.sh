#!/bin/bash
# Initialize .env file with secure randomly-generated secrets
# Run this script once after deploying files to the server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

echo "=== Initializing .env Configuration ==="
echo ""

# Check if .env already exists
if [ -f "$ENV_FILE" ]; then
    echo "WARNING: .env file already exists at $ENV_FILE"
    read -p "Overwrite it? This will regenerate all secrets! (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted. Keeping existing .env file."
        exit 0
    fi
    # Backup existing file
    cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    echo "Backed up existing .env file"
fi

# Get server hostname or use default
MATRIX_DOMAIN="${MATRIX_DOMAIN:-matrix.rumpusroom.xyz}"
ELEMENT_DOMAIN="${ELEMENT_DOMAIN:-element.rumpusroom.xyz}"
SYNAPSE_SERVER_NAME="${SYNAPSE_SERVER_NAME:-$MATRIX_DOMAIN}"
TURN_REALM="${TURN_REALM:-$MATRIX_DOMAIN}"

# Auto-detect protocol based on domain (http for localhost, https for production)
if [[ "$MATRIX_DOMAIN" == "localhost"* ]]; then
    MATRIX_PROTOCOL="${MATRIX_PROTOCOL:-http}"
    MATRIX_PORT="${MATRIX_PORT:-:8008}"
    MAS_PORT="${MAS_PORT:-:8090}"  # MAS public port for local development
else
    MATRIX_PROTOCOL="${MATRIX_PROTOCOL:-https}"
    MATRIX_PORT="${MATRIX_PORT:-}"  # No port for production (default 443)
    MAS_PORT="${MAS_PORT:-}"  # No port for production (nginx proxies at standard HTTPS port)
fi

if [[ "$ELEMENT_DOMAIN" == "localhost"* ]]; then
    ELEMENT_PROTOCOL="${ELEMENT_PROTOCOL:-http}"
    ELEMENT_PORT="${ELEMENT_PORT:-:8080}"
else
    ELEMENT_PROTOCOL="${ELEMENT_PROTOCOL:-https}"
    ELEMENT_PORT="${ELEMENT_PORT:-}"  # No port for production
fi

# MAS public base URL (where MAS is accessible from outside)
# In production: https://matrix.domain/ (nginx proxies /_auth to MAS)
# In local: http://localhost:8090/ (direct access to MAS)
MAS_PUBLIC_BASE="${MAS_PUBLIC_BASE:-${MATRIX_PROTOCOL}://${MATRIX_DOMAIN}${MAS_PORT}/}"

# Generate secure random secrets
echo "Generating secure random secrets..."
SECRETS_POSTGRES_PASSWORD=$(openssl rand -hex 32)
SECRETS_TURN_SHARED_SECRET=$(openssl rand -hex 32)

# MAS (Matrix Authentication Service) secrets
MAS_DB_PASSWORD=$(openssl rand -hex 32)
MAS_ENCRYPTION_SECRET=$(openssl rand -hex 32)
MAS_KEY_ID=$(openssl rand -hex 8)
MAS_SYNAPSE_SHARED_SECRET=$(openssl rand -hex 32)
MAS_ADMIN_TOKEN=$(openssl rand -hex 32)

# Generate RSA signing key for MAS (PEM format)
echo "Generating MAS RSA signing key..."
MAS_KEYS_DIR="$SCRIPT_DIR/../mas/keys"
mkdir -p "$MAS_KEYS_DIR"
chmod 700 "$MAS_KEYS_DIR"

# Generate RSA private key (2048-bit)
openssl genrsa -out "$MAS_KEYS_DIR/signing-key.pem" 2048 2>/dev/null
chmod 600 "$MAS_KEYS_DIR/signing-key.pem"
echo "✓ Generated RSA signing key at $MAS_KEYS_DIR/signing-key.pem"

# Write Docker secret for postgres password (used by postgres container via POSTGRES_PASSWORD_FILE)
SECRETS_DIR="$SCRIPT_DIR/../secrets"
mkdir -p "$SECRETS_DIR"
echo -n "$SECRETS_POSTGRES_PASSWORD" > "$SECRETS_DIR/postgres_password"
chmod 600 "$SECRETS_DIR/postgres_password"
echo "✓ Docker secret written to $SECRETS_DIR/postgres_password"

# Create .env file
cat > "$ENV_FILE" << EOF
# Matrix Synapse Configuration
# Generated: $(date)
# 
# IMPORTANT: Keep this file secure! Contains sensitive credentials.

# Domain Configuration
MATRIX_DOMAIN=$MATRIX_DOMAIN
ELEMENT_DOMAIN=$ELEMENT_DOMAIN
MATRIX_PROTOCOL=$MATRIX_PROTOCOL
ELEMENT_PROTOCOL=$ELEMENT_PROTOCOL
MATRIX_PORT=$MATRIX_PORT
ELEMENT_PORT=$ELEMENT_PORT
MAS_PORT=$MAS_PORT
MAS_PUBLIC_BASE=$MAS_PUBLIC_BASE

# Synapse Configuration
SYNAPSE_SERVER_NAME=$SYNAPSE_SERVER_NAME
SYNAPSE_REPORT_STATS=no

# PostgreSQL Database
SECRETS_POSTGRES_PASSWORD=$SECRETS_POSTGRES_PASSWORD

# TURN/STUN Server (for voice/video calls)
SECRETS_TURN_SHARED_SECRET=$SECRETS_TURN_SHARED_SECRET
TURN_REALM=$TURN_REALM

# Matrix Authentication Service (MAS) - OIDC/Phone Auth
MAS_DB_PASSWORD=$MAS_DB_PASSWORD
MAS_ENCRYPTION_SECRET=$MAS_ENCRYPTION_SECRET
MAS_KEY_ID=$MAS_KEY_ID
MAS_SYNAPSE_SHARED_SECRET=$MAS_SYNAPSE_SHARED_SECRET
MAS_ADMIN_TOKEN=$MAS_ADMIN_TOKEN
EOF

# Secure the file
chmod 600 "$ENV_FILE"

echo ""
echo "✓ .env file created successfully!"
echo "✓ Permissions set to 600 (owner read/write only)"
echo ""
echo "Configuration:"
echo "  Server:    $SYNAPSE_SERVER_NAME"
echo "  Location:  $ENV_FILE"
echo ""
echo "🔒 IMPORTANT: This file contains sensitive secrets!"
echo "   - Never commit it to git (already in .gitignore)"
echo "   - Keep backups in a secure location"
echo "   - Regenerating this file will break existing installations"
echo ""
