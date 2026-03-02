#!/bin/bash
# Deploy Matrix configuration from GitHub to server
# Supports both GitHub Deploy Keys and rsync methods

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
GITHUB_REPO="${GITHUB_REPO:-git@github.com:yourusername/matrix.git}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
SERVER_DEPLOY_DIR="/opt/matrix/app"

echo "=== Matrix Deployment Script ==="
echo ""
echo "This script supports two deployment methods:"
echo "1. GitHub Deploy (clone/pull from private GitHub repo)"
echo "2. rsync Deploy (copy files directly from local machine)"
echo ""

# Detect if we're running on the server or locally
if [ -f "/etc/cloud/cloud.cfg" ] || [ "$HOSTNAME" = "matrix-production-server" ]; then
    MODE="server"
    echo "Detected: Running ON server"
else
    MODE="local"
    echo "Detected: Running from LOCAL machine"
fi

deploy_from_github() {
    echo ""
    echo "=== Deploying from GitHub ==="
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        echo "Error: git is not installed"
        exit 1
    fi
    
    # Create deploy directory if it doesn't exist
    sudo mkdir -p "$SERVER_DEPLOY_DIR"
    sudo chown -R $USER:$USER "$SERVER_DEPLOY_DIR"
    
    if [ -d "$SERVER_DEPLOY_DIR/.git" ]; then
        echo "Repository exists, pulling latest changes..."
        cd "$SERVER_DEPLOY_DIR"
        git fetch origin
        git reset --hard origin/$GITHUB_BRANCH
        echo "✓ Updated to latest version"
    else
        echo "Cloning repository..."
        git clone -b "$GITHUB_BRANCH" "$GITHUB_REPO" "$SERVER_DEPLOY_DIR"
        echo "✓ Repository cloned"
    fi
    
    cd "$SERVER_DEPLOY_DIR"
    echo "Current commit: $(git rev-parse --short HEAD)"
    echo "Last commit message: $(git log -1 --pretty=%B)"
}

deploy_from_local() {
    echo ""
    echo "=== Deploying via rsync ===" 
    
    # Get server IP from terraform
    cd "$PROJECT_ROOT/infra"
    SERVER_IP=$(terraform output -raw server_public_ip 2>/dev/null)
    
    if [ -z "$SERVER_IP" ]; then
        echo "Error: Could not get server IP from terraform"
        echo "Please ensure infrastructure is deployed: cd infra && terraform apply"
        exit 1
    fi
    
    echo "Target server: $SERVER_IP"
    echo "Deploying from: $PROJECT_ROOT"
    echo ""

    # Render synapse/homeserver.yaml from template (substitutes secrets from .env)
    if [ -f "$PROJECT_ROOT/.env" ]; then
        echo "Rendering config templates..."
        set -a && source "$PROJECT_ROOT/.env" && set +a
        envsubst < "$PROJECT_ROOT/synapse/homeserver.yaml.template" \
                 > "$PROJECT_ROOT/synapse/homeserver.yaml"
        echo "  ✓ synapse/homeserver.yaml rendered"
        
        export MAS_SIGNING_KEY_INDENTED="$(echo "$MAS_SIGNING_KEY" | awk '{print "        " $0}')"
        envsubst < "$PROJECT_ROOT/mas/config.yaml.template" \
                 > "$PROJECT_ROOT/mas/config.yaml"
        echo "  ✓ mas/config.yaml rendered"

        envsubst < "$PROJECT_ROOT/element-web/config.json.template" \
                 > "$PROJECT_ROOT/element-web/config.json"
        echo "  ✓ element-web/config.json rendered"

        envsubst < "$PROJECT_ROOT/element-call/config.json.template" \
                 > "$PROJECT_ROOT/element-call/config.json"
        echo "  ✓ element-call/config.json rendered"

        envsubst < "$PROJECT_ROOT/livekit/config.yaml.template" \
                 > "$PROJECT_ROOT/livekit/config.yaml"
        echo "  ✓ livekit/config.yaml rendered"

        mkdir -p "$PROJECT_ROOT/telemetry"
        envsubst < "$PROJECT_ROOT/telemetry/alertmanager.yml.template" \
                 > "$PROJECT_ROOT/telemetry/alertmanager.yml"
        echo "  ✓ telemetry/alertmanager.yml rendered"

        # Generate Nginx htpasswd for Grafana using the secure postgres password
        # This requires apache2-utils/httpd-tools installed locally or on server
        if command -v htpasswd >/dev/null 2>&1; then
            htpasswd -b -c "$PROJECT_ROOT/nginx/.htpasswd" admin "$SECRETS_POSTGRES_PASSWORD"
            echo "  ✓ nginx/.htpasswd generated for Grafana auth"
        else
            echo "⚠️  htpasswd command not found. Skipping proxy auth generation."
        fi
    else
        echo "⚠️  No .env file found — template config files will be sent as-is"
    fi

    rsync -avz \
        --exclude='.git' \
        --exclude='infra/.terraform' \
        --exclude='infra/*.tfstate*' \
        --exclude='infra/terraform.tfvars' \
        --exclude='.env' \
        --exclude='.archive' \
        --exclude='synapse_data' \
        --exclude='postgres_data' \
        --exclude='tmp' \
        -e "ssh -i ~/.ssh/id_ed25519" \
        "$PROJECT_ROOT/" \
        "ubuntu@$SERVER_IP:$SERVER_DEPLOY_DIR/"
    
    # Ensure Docker secrets directory has correct permissions on server
    ssh -i ~/.ssh/id_ed25519 "ubuntu@$SERVER_IP" \
        "chmod 700 $SERVER_DEPLOY_DIR/secrets && chmod 600 $SERVER_DEPLOY_DIR/secrets/* 2>/dev/null || true"
    
    echo ""
    echo "✓ Files deployed to ubuntu@$SERVER_IP:$SERVER_DEPLOY_DIR"
}

setup_github_deploy_key() {
    echo ""
    echo "=== Setting up GitHub Deploy Key ==="
    echo ""
    echo "To deploy from private GitHub repos, you need to set up a deploy key:"
    echo ""
    echo "1. Generate SSH key on server:"
    echo "   ssh-keygen -t ed25519 -C 'matrix-deploy' -f ~/.ssh/matrix-deploy-key -N ''"
    echo ""
    echo "2. Add deploy key to GitHub repository:"
    echo "   - Go to: https://github.com/yourusername/matrix/settings/keys"
    echo "   - Click 'Add deploy key'"
    echo "   - Title: matrix-production-server"
    echo "   - Key: (paste content of ~/.ssh/matrix-deploy-key.pub)"
    echo "   - Allow write access: NO (read-only is safer)"
    echo ""
    echo "3. Configure git to use the key:"
    echo "   cat >> ~/.ssh/config << 'EOF'"
    echo "Host github.com"
    echo "    IdentityFile ~/.ssh/matrix-deploy-key"
    echo "    StrictHostKeyChecking no"
    echo "EOF"
    echo ""
    echo "4. Update GITHUB_REPO in this script or set environment variable:"
    echo "   export GITHUB_REPO='git@github.com:yourusername/matrix.git'"
    echo ""
    read -p "Press Enter to continue..."
}

# Main logic
case "$MODE" in
    server)
        # Running on server - deploy from GitHub
        if [ ! -f ~/.ssh/matrix-deploy-key ]; then
            echo "WARNING: GitHub deploy key not found at ~/.ssh/matrix-deploy-key"
            setup_github_deploy_key
            exit 1
        fi
        deploy_from_github
        ;;
    local)
        # Running locally - use rsync
        echo "Choose deployment method:"
        echo "1. rsync (copy files from this machine to server)"
        echo "2. GitHub (setup instructions for server-side GitHub deployment)"
        read -p "Enter choice (1 or 2): " choice
        
        case "$choice" in
            1)
                deploy_from_local
                ;;
            2)
                setup_github_deploy_key
                ;;
            *)
                echo "Invalid choice"
                exit 1
                ;;
        esac
        ;;
esac

echo ""
echo "✓ Deployment complete!"
