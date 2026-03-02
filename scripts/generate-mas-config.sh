#!/bin/bash
# Generate MAS config.yaml from template with actual values from .env
# This ensures MAS gets a config with real values, not ${VARIABLE} syntax

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../mas/config.yaml.template"
OUTPUT="$SCRIPT_DIR/../mas/config.yaml"
ENV_FILE="$SCRIPT_DIR/../.env"

# Check if template exists
if [ ! -f "$TEMPLATE" ]; then
    echo "Error: Template not found at $TEMPLATE"
    exit 1
fi

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env not found at $ENV_FILE"
    echo "Run 'make init-env' first"
    exit 1
fi

echo "=== Generating MAS config.yaml from template ==="

# Check for signing key file
SIGNING_KEY_FILE="$SCRIPT_DIR/../mas/keys/signing-key.pem"
if [ ! -f "$SIGNING_KEY_FILE" ]; then
    echo "Error: Signing key not found at $SIGNING_KEY_FILE"
    echo "Run 'make init-env' to generate it"
    exit 1
fi

# Load environment variables
set -a
source "$ENV_FILE"
set +a

# First, substitute environment variables
envsubst < "$TEMPLATE" > "$OUTPUT.tmp"

# Then, inject the PEM key with proper YAML indentation (8 spaces)
# Process line by line to handle multi-line PEM content
{
    while IFS= read -r line; do
        if [[ "$line" == *"__SIGNING_KEY_PLACEHOLDER__"* ]]; then
            # Insert the PEM key with proper indentation
            while IFS= read -r keyline; do
                echo "        $keyline"
            done < "$SIGNING_KEY_FILE"
        else
            echo "$line"
        fi
    done < "$OUTPUT.tmp"
} > "$OUTPUT"

rm "$OUTPUT.tmp"

echo "✓ Generated $OUTPUT with actual secret values"
echo ""
echo "Note: config.yaml is .gitignored (contains secrets)"
echo "      config.yaml.template is version controlled"
