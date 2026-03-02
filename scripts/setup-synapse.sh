#!/bin/bash
# Setup Synapse data directory with correct permissions
# Handles the synapse_data volume ownership issue

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/.."
SYNAPSE_DATA_DIR="$APP_DIR/synapse_data"
SYNAPSE_UID=991
SYNAPSE_GID=991

echo "=== Setting up Synapse Data Directory ==="
echo ""

# Check if docker-compose.yml exists
if [ ! -f "$APP_DIR/docker-compose.yml" ]; then
    echo "Error: docker-compose.yml not found in $APP_DIR"
    exit 1
fi

# Create synapse_data directory if it doesn't exist
if [ ! -d "$SYNAPSE_DATA_DIR" ]; then
    echo "Creating synapse_data directory..."
    mkdir -p "$SYNAPSE_DATA_DIR"
fi

# Check current ownership
CURRENT_OWNER=$(stat -c '%u:%g' "$SYNAPSE_DATA_DIR" 2>/dev/null || stat -f '%u:%g' "$SYNAPSE_DATA_DIR" 2>/dev/null)
echo "Current ownership: $CURRENT_OWNER"

# Set correct ownership
echo "Setting ownership to $SYNAPSE_UID:$SYNAPSE_GID..."
sudo chown -R $SYNAPSE_UID:$SYNAPSE_GID "$SYNAPSE_DATA_DIR"

# Set permissions
sudo chmod 750 "$SYNAPSE_DATA_DIR"

echo "✓ Permissions set correctly"
echo ""

# Check if homeserver.yaml exists
if [ ! -f "$SYNAPSE_DATA_DIR/homeserver.yaml" ]; then
    echo "Homeserver config not found. Generating initial configuration..."
    echo ""
    
    # Check if .env exists
    if [ ! -f "$APP_DIR/.env" ]; then
        echo "Error: .env file not found. Run scripts/init-env.sh first."
        exit 1
    fi
    
    # Start postgres first
    echo "Starting PostgreSQL..."
    cd "$APP_DIR"
    docker compose up -d postgres
    
    # Wait for postgres to be healthy
    echo "Waiting for PostgreSQL to be ready..."
    timeout 60 bash -c 'until docker compose exec -T postgres pg_isready -U synapse > /dev/null 2>&1; do sleep 2; done' || {
        echo "Error: PostgreSQL did not become ready in time"
        exit 1
    }
    echo "✓ PostgreSQL is ready"
    echo ""
    
    # Generate Synapse config
    echo "Generating Synapse configuration..."
    docker compose run --rm synapse generate
    
    echo "✓ Configuration generated"
    echo ""
    
    # Fix ownership again (generation might create files as root)
    echo "Fixing ownership after generation..."
    sudo chown -R $SYNAPSE_UID:$SYNAPSE_GID "$SYNAPSE_DATA_DIR"
    echo "✓ Ownership fixed"
else
    echo "✓ Homeserver config already exists at $SYNAPSE_DATA_DIR/homeserver.yaml"
fi

# Verify final permissions
echo ""
echo "Final verification:"
ls -la "$SYNAPSE_DATA_DIR" | head -5
echo ""
echo "✓ Synapse data directory is ready!"
echo ""
echo "Next steps:"
echo "1. Start all services: docker compose up -d"
echo "2. Create admin user: docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008"
