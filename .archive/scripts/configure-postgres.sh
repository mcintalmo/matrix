#!/bin/bash

# Script to configure PostgreSQL for Synapse
# This script updates the homeserver.yaml to use PostgreSQL instead of SQLite

set -e

echo "🔧 Configuring Synapse to use PostgreSQL..."

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "Please copy .env.example to .env and configure it first."
    exit 1
fi

# Load environment variables
source .env

# Get the volume mount point
SYNAPSE_DATA=$(docker volume inspect matrix_synapse_data --format '{{ .Mountpoint }}' 2>/dev/null)

if [ -z "$SYNAPSE_DATA" ]; then
    echo "❌ Error: synapse_data volume not found!"
    echo "Please run: docker compose run --rm synapse generate"
    exit 1
fi

HOMESERVER_YAML="$SYNAPSE_DATA/homeserver.yaml"

if [ ! -f "$HOMESERVER_YAML" ]; then
    echo "❌ Error: homeserver.yaml not found at $HOMESERVER_YAML"
    echo "Please generate the config first: docker compose run --rm synapse generate"
    exit 1
fi

# Create backup
echo "📦 Creating backup of homeserver.yaml..."
sudo cp "$HOMESERVER_YAML" "$HOMESERVER_YAML.backup.$(date +%Y%m%d_%H%M%S)"

# Create PostgreSQL configuration
cat > /tmp/postgres_config.yaml << EOF
database:
  name: psycopg2
  args:
    user: synapse
    password: $POSTGRES_PASSWORD
    database: synapse
    host: postgres
    port: 5432
    cp_min: 5
    cp_max: 10
EOF

echo "✏️  Updating database configuration..."

# Use Python to safely update the YAML file
python3 << 'PYTHON_SCRIPT'
import yaml
import sys

homeserver_file = sys.argv[1]
postgres_config_file = sys.argv[2]

# Read the homeserver config
with open(homeserver_file, 'r') as f:
    config = yaml.safe_load(f)

# Read the postgres config
with open(postgres_config_file, 'r') as f:
    postgres_config = yaml.safe_load(f)

# Update database configuration
config['database'] = postgres_config['database']

# Write back to homeserver.yaml
with open(homeserver_file, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, sort_keys=False)

print("✅ Database configuration updated successfully!")
PYTHON_SCRIPT

if [ $? -ne 0 ]; then
    echo "❌ Error updating configuration. Trying alternative method..."
    
    # Fallback: Use sed to replace the database section
    sudo sed -i.bak '/^database:/,/^[^ ]/c\
database:\
  name: psycopg2\
  args:\
    user: synapse\
    password: '"$POSTGRES_PASSWORD"'\
    database: synapse\
    host: postgres\
    port: 5432\
    cp_min: 5\
    cp_max: 10\
' "$HOMESERVER_YAML"
    
    echo "✅ Configuration updated using fallback method."
fi

# Clean up
rm /tmp/postgres_config.yaml 2>/dev/null || true

echo ""
echo "✅ PostgreSQL configuration complete!"
echo ""
echo "To enable user registration for testing, add these lines to homeserver.yaml:"
echo "  enable_registration: true"
echo "  enable_registration_without_verification: true"
echo ""
echo "⚠️  WARNING: Only enable registration for local testing!"
echo ""
echo "Now start the services:"
echo "  docker compose up -d"
