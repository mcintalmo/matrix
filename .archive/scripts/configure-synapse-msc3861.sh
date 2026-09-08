#!/bin/bash
# Configure Synapse homeserver.yaml with MSC3861 experimental features
# This must be done in the main homeserver.yaml, not conf.d overrides

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

# Load environment variables
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env not found at $ENV_FILE"
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

echo "=== Configuring Synapse with MSC3861 ===" 

# Check if Synapse container is running
if ! docker compose ps synapse | grep -q "Up"; then
    echo "Starting Synapse to access homeserver.yaml..."
    docker compose up -d synapse
    sleep 5
fi

# Backup existing homeserver.yaml (to local machine)
echo "Creating backup of homeserver.yaml..."
docker compose exec synapse cat /data/homeserver.yaml > "$SCRIPT_DIR/../homeserver.yaml.backup"

# Check if MSC3861 is already configured
if grep -q "msc3861:" "$SCRIPT_DIR/../homeserver.yaml.backup" 2>/dev/null; then
    echo "⚠️  MSC3861 already configured in homeserver.yaml"
    echo "To reconfigure, manually edit the homeserver.yaml in the synapse_data volume"
    exit 0
fi

# Create the MSC3861 configuration block
MSC3861_CONFIG="
# Matrix Authentication Service (MSC3861) Configuration
# Added by configure-synapse-msc3861.sh

# Public base URL for this homeserver (required for MSC3861 well-known)
public_baseurl: \"${MATRIX_PROTOCOL}://${MATRIX_DOMAIN}${MATRIX_PORT}\"

experimental_features:
  msc3861:
    enabled: true
    issuer: \"${MAS_PUBLIC_BASE}\"
    # Override issuer metadata to use internal docker network for Synapse->MAS communication
    issuer_metadata:
      issuer: \"${MAS_PUBLIC_BASE}\"
      introspection_endpoint: \"http://mas:8090/oauth2/introspect\"
      authorization_endpoint: \"${MAS_PUBLIC_BASE}authorize\"
      token_endpoint: \"http://mas:8090/oauth2/token\"
      jwks_uri: \"http://mas:8090/oauth2/keys.json\"
    client_id: \"01HMX5W5W5W5W5W5W5W5W5W5W5\"
    client_auth_method: \"client_secret_basic\"
    client_secret: \"${MAS_SYNAPSE_SHARED_SECRET}\"
    admin_token: \"${MAS_ADMIN_TOKEN}\"
    account_management_url: \"${MAS_PUBLIC_BASE}_auth/account\"

# Disable password authentication (MAS handles all auth)
password_config:
  enabled: false

# Disable registration (MAS handles all registration)
enable_registration: false
"

# Append MSC3861 config to homeserver.yaml locally
echo "Adding MSC3861 configuration..."
echo "$MSC3861_CONFIG" >> "$SCRIPT_DIR/../homeserver.yaml.backup"

# Copy the modified file into the container
echo "Copying updated configuration to container..."
docker compose cp "$SCRIPT_DIR/../homeserver.yaml.backup" synapse:/tmp/homeserver.yaml.new

# Move the file into place (as root to bypass permission issues)
echo "Installing new homeserver.yaml..."
docker compose exec --user root synapse mv /tmp/homeserver.yaml.new /data/homeserver.yaml

# Set proper ownership
docker compose exec --user root synapse chown 991:991 /data/homeserver.yaml

echo "✓ MSC3861 configuration added to homeserver.yaml"
echo ""
echo "Restarting Synapse to apply changes..."
docker compose restart synapse

echo ""
echo "✓ Synapse restarted with MSC3861 enabled"
echo ""
echo "To verify configuration:"
echo "   docker compose exec synapse grep -A 10 'msc3861:' /data/homeserver.yaml"
echo ""
echo "Next steps:"
echo "   1. Check Synapse logs: docker compose logs synapse | grep -i experimental"
echo "   2. Create MAS admin user: make mas-create-admin-local"
