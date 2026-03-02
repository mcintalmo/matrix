#!/bin/bash
# Update local IP address in terraform.tfvars and apply to infrastructure
# This handles VPN IP changes automatically

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TFVARS_FILE="$PROJECT_ROOT/infra/terraform.tfvars"

echo "=== Updating IP Address in Terraform Config ==="

# Check if terraform.tfvars exists
if [ ! -f "$TFVARS_FILE" ]; then
    echo "Error: $TFVARS_FILE not found!"
    echo "Please create it from terraform.tfvars.example first."
    exit 1
fi

# Detect current public IP
echo "Detecting your current public IP address..."
CURRENT_IP=$(curl -s https://api.ipify.org)

if [ -z "$CURRENT_IP" ]; then
    echo "Error: Could not detect current IP address."
    echo "Please check your internet connection."
    exit 1
fi

echo "Current public IP: $CURRENT_IP"

# Check if IP is already in terraform.tfvars
CURRENT_TFVAR_IP=$(grep "my_ip_cidr" "$TFVARS_FILE" | cut -d'"' -f2 | cut -d'/' -f1)

if [ "$CURRENT_IP" = "$CURRENT_TFVAR_IP" ]; then
    echo "✓ IP address is already up to date in terraform.tfvars"
    exit 0
fi

# Backup current terraform.tfvars
cp "$TFVARS_FILE" "$TFVARS_FILE.backup"
echo "Backed up current config to terraform.tfvars.backup"

# Update the my_ip_cidr value
sed -i.tmp "s|my_ip_cidr *= *\"[0-9.]*\/[0-9]*\"|my_ip_cidr = \"${CURRENT_IP}/32\"|g" "$TFVARS_FILE"
rm -f "$TFVARS_FILE.tmp"

echo "✓ Updated terraform.tfvars: my_ip_cidr = \"${CURRENT_IP}/32\""

# Ask if user wants to apply changes
read -p "Apply changes to infrastructure? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Applying Terraform changes..."
    cd "$PROJECT_ROOT/infra"
    terraform apply -target=oci_core_security_list.matrix_sl -auto-approve
    echo ""
    echo "✓ Infrastructure updated successfully!"
else
    echo "Skipped infrastructure update. Run 'make tf-apply' or 'cd infra && terraform apply' to apply later."
fi

echo ""
echo "Old IP: $CURRENT_TFVAR_IP"
echo "New IP: $CURRENT_IP"
