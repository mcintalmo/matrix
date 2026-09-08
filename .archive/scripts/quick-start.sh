#!/bin/bash

# Quick Start Script for Matrix Synapse Local Setup
# This script automates the entire setup process

set -e

echo "🚀 Matrix Synapse Quick Start"
echo "=============================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Docker is not running!${NC}"
    echo "Please start Docker Desktop and try again."
    exit 1
fi

# Check if docker compose is available
if ! docker compose version > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Docker Compose is not available!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Docker is running${NC}"
echo ""

# Step 1: Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "📝 Creating .env file..."
    cp .env.example .env
    
    # Generate a random password
    RANDOM_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    # Update the password in .env
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/CHANGE_THIS_PASSWORD/$RANDOM_PASSWORD/" .env
    else
        sed -i "s/CHANGE_THIS_PASSWORD/$RANDOM_PASSWORD/" .env
    fi
    
    echo -e "${GREEN}✅ Created .env with generated password${NC}"
else
    echo -e "${YELLOW}ℹ️  .env file already exists, skipping...${NC}"
fi

echo ""

# Step 2: Generate Synapse configuration
echo "🔧 Generating Synapse configuration..."

# Check if volume exists and is populated
VOLUME_EXISTS=false
CONFIG_EXISTS=false

if docker volume inspect matrix_synapse_data > /dev/null 2>&1; then
    VOLUME_EXISTS=true
    SYNAPSE_DATA=$(docker volume inspect matrix_synapse_data --format '{{ .Mountpoint }}')
    
    # Check if homeserver.yaml exists in the volume
    if [ -f "$SYNAPSE_DATA/homeserver.yaml" ] || sudo test -f "$SYNAPSE_DATA/homeserver.yaml" 2>/dev/null; then
        CONFIG_EXISTS=true
    fi
fi

if [ "$VOLUME_EXISTS" = true ] && [ "$CONFIG_EXISTS" = true ]; then
    echo -e "${YELLOW}ℹ️  Synapse configuration already exists${NC}"
    read -p "Do you want to regenerate the configuration? This will DELETE all data! (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  Removing old data..."
        docker compose down -v
        SKIP_GENERATE=false
    else
        echo "Keeping existing configuration..."
        SKIP_GENERATE=true
    fi
elif [ "$VOLUME_EXISTS" = true ] && [ "$CONFIG_EXISTS" = false ]; then
    echo -e "${YELLOW}⚠️  Volume exists but configuration is incomplete${NC}"
    echo "🗑️  Recreating volume..."
    docker compose down -v
    SKIP_GENERATE=false
fi

if [ "$SKIP_GENERATE" != "true" ]; then
    echo "Generating Synapse configuration..."
    if ! docker compose run --rm synapse generate; then
        echo -e "${RED}❌ Error: Failed to generate Synapse configuration${NC}"
        exit 1
    fi
    
    # Verify the file was created using Docker (works on macOS and Linux)
    echo "Verifying configuration was created..."
    if docker compose run --rm --entrypoint sh synapse -c "test -f /data/homeserver.yaml && echo 'File exists'" | grep -q "File exists"; then
        echo -e "${GREEN}✅ Synapse configuration generated successfully${NC}"
    else
        echo -e "${RED}❌ Error: Configuration generation failed${NC}"
        echo "The generate command ran but homeserver.yaml was not created."
        exit 1
    fi
fi

echo ""

# Step 3: Configure PostgreSQL
echo "🔧 Configuring PostgreSQL connection..."

# Load the password from .env
source .env

# Use Docker to update the configuration (works on macOS and Linux)
# Create a Python script that will run inside a temporary container
cat > /tmp/update_synapse_config.py << 'PYTHONEOF'
import sys
import re

postgres_password = sys.argv[1]

# Read the homeserver.yaml from /data volume
with open('/data/homeserver.yaml', 'r') as f:
    content = f.read()

# Create backup
with open('/data/homeserver.yaml.backup', 'w') as f:
    f.write(content)

# PostgreSQL configuration
postgres_config = f"""database:
  name: psycopg2
  args:
    user: synapse
    password: {postgres_password}
    database: synapse
    host: postgres
    port: 5432
    cp_min: 5
    cp_max: 10"""

# Replace the database section (handles both SQLite and existing psycopg2)
# Match from 'database:' to the next top-level key (no leading spaces)
pattern = r'database:.*?(?=\n[a-z_]+:|$)'
content = re.sub(pattern, postgres_config, content, flags=re.DOTALL)

# Write back
with open('/data/homeserver.yaml', 'w') as f:
    f.write(content)

print("✓ Database configuration updated successfully")
PYTHONEOF

echo "✏️  Updating database configuration..."

# Run the Python script inside a Synapse container
if docker compose run --rm --entrypoint python3 -v /tmp/update_synapse_config.py:/tmp/update_config.py:ro synapse /tmp/update_config.py "$POSTGRES_PASSWORD"; then
    echo -e "${GREEN}✅ PostgreSQL configuration complete${NC}"
else
    echo -e "${RED}❌ Error: Failed to update database configuration${NC}"
    echo "Please check the logs and try manual configuration."
    rm /tmp/update_synapse_config.py 2>/dev/null || true
    exit 1
fi

# Clean up
rm /tmp/update_synapse_config.py 2>/dev/null || true

# Enable registration for easy testing (optional)
echo ""
read -p "Enable user registration for easy testing? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "⚠️  Enabling registration (ONLY for local testing)..."
    
    # Use Docker to enable registration
    cat > /tmp/enable_registration.sh << 'SHELLEOF'
#!/bin/sh
if ! grep -q "enable_registration:" /data/homeserver.yaml; then
    echo "" >> /data/homeserver.yaml
    echo "enable_registration: true" >> /data/homeserver.yaml
    echo "enable_registration_without_verification: true" >> /data/homeserver.yaml
else
    sed -i 's/enable_registration: false/enable_registration: true/' /data/homeserver.yaml
fi
echo "Registration enabled"
SHELLEOF
    
    chmod +x /tmp/enable_registration.sh
    docker compose run --rm --entrypoint sh -v /tmp/enable_registration.sh:/tmp/enable_reg.sh:ro synapse /tmp/enable_reg.sh
    rm /tmp/enable_registration.sh
    
    echo -e "${GREEN}✅ Registration enabled${NC}"
else
    echo "Registration will remain disabled (use command-line to create users)"
fi

echo ""
echo -e "${GREEN}✅ PostgreSQL configuration complete${NC}"

# Step 4: Start services
echo ""
echo "🚀 Starting services..."
docker compose up -d

echo ""
echo "⏳ Waiting for services to be healthy..."
sleep 5

# Wait for Synapse to be healthy
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
echo -e "${GREEN}║                    🎉 Setup Complete! 🎉                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Create an admin user:"
echo -e "   ${YELLOW}docker compose exec synapse register_new_matrix_user http://localhost:8008 -c /data/homeserver.yaml -a${NC}"
echo ""
echo "2. Open Element Web in your browser:"
echo -e "   ${YELLOW}http://localhost:8080${NC}"
echo ""
echo "3. Sign in with your username: @username:localhost"
echo ""
echo "4. Start chatting! Create a room and send a message to test."
echo ""
echo "Useful commands:"
echo "  - View logs: docker compose logs -f"
echo "  - Stop services: docker compose down"
echo "  - Restart: docker compose restart"
echo ""
echo "For more information, see README.md"
echo ""
