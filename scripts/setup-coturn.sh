#!/bin/bash

# Script to configure coturn for Matrix Synapse
# This adds TURN server configuration to Synapse for voice/video calls

set -e

echo "🔧 Configuring coturn for Matrix Synapse"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Load environment variables
if [ ! -f .env ]; then
    echo -e "${RED}❌ Error: .env file not found!${NC}"
    exit 1
fi

source .env

# Check if TURN_SHARED_SECRET is set
if [ -z "$TURN_SHARED_SECRET" ] || [ "$TURN_SHARED_SECRET" = "CHANGE_THIS_TURN_SECRET" ]; then
    echo -e "${YELLOW}⚠️  Generating random TURN shared secret...${NC}"
    TURN_SHARED_SECRET=$(openssl rand -hex 32)
    
    # Update .env file
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/TURN_SHARED_SECRET=.*/TURN_SHARED_SECRET=$TURN_SHARED_SECRET/" .env
    else
        sed -i "s/TURN_SHARED_SECRET=.*/TURN_SHARED_SECRET=$TURN_SHARED_SECRET/" .env
    fi
    echo -e "${GREEN}✅ Generated TURN shared secret${NC}"
fi

# Update coturn configuration
echo "📝 Updating coturn configuration..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/static-auth-secret=.*/static-auth-secret=$TURN_SHARED_SECRET/" coturn/turnserver.conf
else
    sed -i "s/static-auth-secret=.*/static-auth-secret=$TURN_SHARED_SECRET/" coturn/turnserver.conf
fi
echo -e "${GREEN}✅ Updated coturn config${NC}"

# Create Synapse TURN configuration
echo "📝 Creating Synapse TURN configuration..."

cat > /tmp/add_turn_config.py << 'PYTHONEOF'
import sys
import os

turn_shared_secret = sys.argv[1]
turn_realm = sys.argv[2]

# Read homeserver.yaml
with open('/data/homeserver.yaml', 'r') as f:
    lines = f.readlines()

# Check if TURN config already exists
has_turn_config = any('turn_uris:' in line for line in lines)

if has_turn_config:
    print("TURN configuration already exists in homeserver.yaml")
    sys.exit(0)

# Add TURN configuration at the end
turn_config = f"""
# TURN server configuration for voice/video calls
turn_uris:
  - "turn:{turn_realm}:3478?transport=udp"
  - "turn:{turn_realm}:3478?transport=tcp"

turn_shared_secret: "{turn_shared_secret}"

# Allow guests to use TURN server
turn_allow_guests: true

# User lifetime for TURN credentials (in milliseconds)
turn_user_lifetime: 86400000
"""

# Write back
with open('/data/homeserver.yaml', 'a') as f:
    f.write(turn_config)

print("✓ Added TURN configuration to homeserver.yaml")
PYTHONEOF

echo "✏️  Adding TURN configuration to Synapse..."

# Run the Python script inside a Synapse container
if docker compose run --rm --entrypoint python3 -v /tmp/add_turn_config.py:/tmp/add_turn.py:ro synapse /tmp/add_turn.py "$TURN_SHARED_SECRET" "${TURN_REALM:-localhost}"; then
    echo -e "${GREEN}✅ Synapse TURN configuration complete${NC}"
else
    echo -e "${RED}❌ Error: Failed to update Synapse configuration${NC}"
    rm /tmp/add_turn_config.py 2>/dev/null || true
    exit 1
fi

# Clean up
rm /tmp/add_turn_config.py 2>/dev/null || true

echo ""
echo "🚀 Starting coturn service..."
docker compose up -d coturn

echo ""
echo "⏳ Waiting for coturn to start..."
sleep 3

if docker compose ps coturn | grep -q "Up"; then
    echo -e "${GREEN}✅ coturn is running!${NC}"
else
    echo -e "${RED}❌ coturn failed to start. Check logs: docker compose logs coturn${NC}"
    exit 1
fi

echo ""
echo "🔄 Restarting Synapse to apply TURN configuration..."
docker compose restart synapse

echo ""
echo "⏳ Waiting for Synapse to restart..."
sleep 5

# Wait for Synapse health check
for i in {1..30}; do
    if curl -sf http://localhost:8008/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Synapse is healthy!${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}❌ Synapse failed to start. Check logs: docker compose logs synapse${NC}"
        exit 1
    fi
    echo -n "."
    sleep 2
done

echo ""
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              🎉 coturn Setup Complete! 🎉                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Voice and video calls are now enabled!"
echo ""
echo "To test:"
echo "1. Open Element Web: http://localhost:8080"
echo "2. Start a 1:1 call with another user"
echo "3. Audio/video should work through the TURN server"
echo ""
echo "Configuration:"
echo "  - TURN Server: localhost:3478"
echo "  - Realm: ${TURN_REALM:-localhost}"
echo "  - UDP Ports: 49152-49172"
echo ""
echo "View logs:"
echo "  docker compose logs -f coturn"
echo ""
