#!/bin/bash
# Generate Synapse custom.yaml from template with actual values from .env

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../config/custom.yaml.template"
OUTPUT="$SCRIPT_DIR/../config/custom.yaml"
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

echo "=== Generating Synapse custom.yaml from template ==="

# Load environment variables
set -a
source "$ENV_FILE"
set +a

# Use envsubst to replace ${VARIABLES} with actual values
envsubst < "$TEMPLATE" > "$OUTPUT"

echo "✓ Generated $OUTPUT with actual secret values"
echo ""
echo "Note: custom.yaml is .gitignored (contains secrets)"
echo "      custom.yaml.template is version controlled"
