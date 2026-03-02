#!/bin/bash

# Script to configure TURN server settings in Synapse
# Run this after initial setup to enable voice/video calls

set -e

echo "🔄 Configuring TURN server for Synapse..."
echo ""

# Check if synapse is running
if ! docker compose ps synapse | grep -q "Up"; then
    echo "❌ Error: Synapse is not running!"
    echo "Start it with: docker compose up -d"
    exit 1
fi

# Load environment variables
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "Please run ./scripts/quick-start.sh first"
    exit 1
fi

source .env

# Check if TURN secret is set
if [ -z "$TURN_SHARED_SECRET" ] || [ "$TURN_SHARED_SECRET" = "CHANGE_THIS_TURN_SECRET" ]; then
    echo "⚠️  Warning: TURN_SHARED_SECRET not set in .env"
    echo "Generating a random secret..."
    TURN_SHARED_SECRET=$(openssl rand -hex 32)
    
    # Update .env file
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/TURN_SHARED_SECRET=.*/TURN_SHARED_SECRET=$TURN_SHARED_SECRET/" .env
    else
        sed -i "s/TURN_SHARED_SECRET=.*/TURN_SHARED_SECRET=$TURN_SHARED_SECRET/" .env
    fi
    
    echo "✅ Generated and saved TURN secret to .env"
fi

# Update coturn configuration with the secret
echo "Updating coturn configuration..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/static-auth-secret=.*/static-auth-secret=$TURN_SHARED_SECRET/" coturn/turnserver.conf
else
    sed -i "s/static-auth-secret=.*/static-auth-secret=$TURN_SHARED_SECRET/" coturn/turnserver.conf
fi

# Determine the realm (server name)
TURN_REALM=${SYNAPSE_SERVER_NAME:-localhost}

echo "Updating coturn realm to: $TURN_REALM"
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/realm=.*/realm=$TURN_REALM/" coturn/turnserver.conf
else
    sed -i "s/realm=.*/realm=$TURN_REALM/" coturn/turnserver.conf
fi

# Create TURN configuration for Synapse
cat > /tmp/turn_config.yaml << EOF
# TURN server configuration
turn_uris:
  - "turn:localhost:3478?transport=udp"
  - "turn:localhost:3478?transport=tcp"
  - "turns:localhost:5349?transport=udp"
  - "turns:localhost:5349?transport=tcp"

turn_shared_secret: "${TURN_SHARED_SECRET}"

# How long temporary TURN credentials are valid for (in milliseconds)
turn_user_lifetime: 86400000  # 24 hours

# Whether to allow guests to use the TURN server
turn_allow_guests: false
EOF

echo "Adding TURN configuration to Synapse..."

# Use Docker to append TURN config to homeserver.yaml
cat > /tmp/add_turn_config.py << 'PYTHONEOF'
import sys
import re

turn_secret = sys.argv[1]

# Read the homeserver.yaml
with open('/data/homeserver.yaml', 'r') as f:
    content = f.read()

# Create backup
with open('/data/homeserver.yaml.turn_backup', 'w') as f:
    f.write(content)

# Remove existing TURN configuration if present
content = re.sub(r'\n# TURN server configuration.*?turn_allow_guests: (true|false)\n', 
                 '', content, flags=re.DOTALL)
content = re.sub(r'\nturn_uris:.*?turn_allow_guests: (true|false)\n', 
                 '', content, flags=re.DOTALL)

# Add new TURN configuration at the end
turn_config = f"""
# TURN server configuration
turn_uris:
  - "turn:localhost:3478?transport=udp"
  - "turn:localhost:3478?transport=tcp"
  - "turns:localhost:5349?transport=udp"
  - "turns:localhost:5349?transport=tcp"

turn_shared_secret: "{turn_secret}"

# How long temporary TURN credentials are valid for (in milliseconds)
turn_user_lifetime: 86400000  # 24 hours

# Whether to allow guests to use the TURN server
turn_allow_guests: false
"""

content = content.rstrip() + '\n' + turn_config

# Write back
with open('/data/homeserver.yaml', 'w') as f:
    f.write(content)

print("✓ TURN configuration added successfully")
PYTHONEOF

if docker compose run --rm --entrypoint python3 -v /tmp/add_turn_config.py:/tmp/add_turn.py:ro synapse /tmp/add_turn.py "$TURN_SHARED_SECRET"; then
    echo "✅ TURN configuration updated in homeserver.yaml"
else
    echo "❌ Error: Failed to update TURN configuration"
    rm /tmp/add_turn_config.py /tmp/turn_config.yaml 2>/dev/null || true
    exit 1
fi

# Clean up
rm /tmp/add_turn_config.py /tmp/turn_config.yaml 2>/dev/null || true

echo ""
echo "🚀 Restarting services to apply TURN configuration..."
docker compose restart synapse coturn

echo ""
echo "⏳ Waiting for services to be healthy..."
sleep 5

# Wait for Synapse to be healthy
for i in {1..20}; do
    if curl -sf http://localhost:8008/health > /dev/null 2>&1; then
        echo "✅ Synapse is healthy!"
        break
    fi
    if [ $i -eq 20 ]; then
        echo "⚠️  Synapse may not be fully ready yet. Check logs: docker compose logs synapse"
    fi
    echo -n "."
    sleep 2
done

echo ""
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              🎉 TURN Server Configured! 🎉                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Voice and video calls are now enabled!"
echo ""
echo "To test:"
echo "  1. Open Element Web: http://localhost:8080"
echo "  2. Create a room and invite another user"
echo "  3. Click the call button (phone icon)"
echo "  4. Start a voice or video call"
echo ""
echo "Troubleshooting:"
echo "  - View coturn logs: docker compose logs coturn"
echo "  - View synapse logs: docker compose logs synapse"
echo "  - Check TURN connectivity: https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/"
echo ""
