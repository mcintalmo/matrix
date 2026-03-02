#!/bin/bash
set -e

echo "Generating random secrets for configuration..."

SECRETS_POSTGRES_PASSWORD=$(openssl rand -hex 32)
MAS_SYNAPSE_SHARED_SECRET=$(openssl rand -hex 32)
MAS_ADMIN_TOKEN=$(openssl rand -hex 32)
MAS_ENCRYPTION_SECRET=$(openssl rand -hex 32)

echo "Please insert your Discord Auth Credentials below:"
read -p "Discord Client ID: " DISCORD_CLIENT_ID
read -p "Discord Client Secret: " DISCORD_CLIENT_SECRET

echo "Please insert your Google Auth Credentials below:"
read -p "Google Client ID: " GOOGLE_CLIENT_ID
read -p "Google Client Secret: " GOOGLE_CLIENT_SECRET

echo "Please insert your Gmail App Password below:"
read -p "Gmail App Password (16 chars): " GMAIL_APP_PASSWORD


echo "Generating EC signing key for MAS..."
SIGNING_KEY_PEM=$(openssl ecparam -name prime256v1 -genkey -noout)
# Indent the key for YAML format
INDENTED_KEY=$(echo "$SIGNING_KEY_PEM" | sed 's/^/        /')

echo "Patching Docker Compose..."
sed -i.bak "s/__POSTGRES_PASSWORD__/$SECRETS_POSTGRES_PASSWORD/g" docker-compose.yml

echo "Patching Synapse Configuration Snippet..."
sed -i.bak "s/__MAS_SYNAPSE_SHARED_SECRET__/$MAS_SYNAPSE_SHARED_SECRET/g" homeserver.yaml.snippet
sed -i.bak "s/__MAS_ADMIN_TOKEN__/$MAS_ADMIN_TOKEN/g" homeserver.yaml.snippet

echo "Patching MAS Configuration Snippet..."
sed -i.bak "s/__POSTGRES_PASSWORD__/$POSTGRES_PASSWORD/g" config.yaml.snippet
sed -i.bak "s/__MAS_ENCRYPTION_SECRET__/$MAS_ENCRYPTION_SECRET/g" config.yaml.snippet
sed -i.bak "s/__MAS_SYNAPSE_SHARED_SECRET__/$MAS_SYNAPSE_SHARED_SECRET/g" config.yaml.snippet
sed -i.bak "s/__DISCORD_CLIENT_ID__/$DISCORD_CLIENT_ID/g" config.yaml.snippet
sed -i.bak "s/__DISCORD_CLIENT_SECRET__/$DISCORD_CLIENT_SECRET/g" config.yaml.snippet
sed -i.bak "s/__GOOGLE_CLIENT_ID__/$GOOGLE_CLIENT_ID/g" config.yaml.snippet
sed -i.bak "s/__GOOGLE_CLIENT_SECRET__/$GOOGLE_CLIENT_SECRET/g" config.yaml.snippet
sed -i.bak "s/__GMAIL_APP_PASSWORD__/$GMAIL_APP_PASSWORD/g" config.yaml.snippet

# Replace the placeholder with the actual indented PEM block using perl
export INDENTED_KEY
perl -0777 -pi.bak -e 's/__SIGNING_KEY_PLACEHOLDER__/$ENV{INDENTED_KEY}/g' config.yaml.snippet

echo "Secrets injected successfully! Review the snippets to integrate into your main configurations."
