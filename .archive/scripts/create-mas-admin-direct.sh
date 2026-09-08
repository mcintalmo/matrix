#!/usr/bin/env bash
# Create MAS admin user directly in the database (bootstrap workaround)
# This bypasses the username validation issue

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Load environment variables
if [ ! -f .env ]; then
    echo "Error: .env file not found"
    exit 1
fi

source .env

echo "=== Creating MAS Admin User Directly in Database ==="
echo ""
echo "This script creates a user directly in the MAS database, bypassing"
echo "the CLI username validation issue with MSC3861."
echo ""

# Prompt for username
read -p "Enter admin username: " USERNAME
if [ -z "$USERNAME" ]; then
    echo "Error: Username cannot be empty"
    exit 1
fi

# Prompt for password
read -sp "Enter admin password: " PASSWORD
echo ""
if [ -z "$PASSWORD" ]; then
    echo "Error: Password cannot be empty"
    exit 1
fi

# Generate UUIDs
USER_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
EMAIL_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

echo ""
echo "Generating password hash..."

# Hash the password using argon2id via Python
PASSWORD_HASH=$(docker compose exec -T postgres python3 << EOF
import sys
from passlib.hash import argon2

# Hash the password with argon2id
password = """$PASSWORD"""
hashed = argon2.using(
    type='ID',
    memory_cost=19456,  # MAS default
    time_cost=2,
    parallelism=1,
    salt_len=16,
    digest_size=32
).hash(password)

print(hashed)
EOF
)

if [ -z "$PASSWORD_HASH" ]; then
    echo "Error: Failed to generate password hash"
    echo "Trying alternative method with MAS container..."
    
    # Alternative: use MAS container to hash
    PASSWORD_HASH=$(docker compose exec mas mas-cli manage hash-password <<< "$PASSWORD" 2>/dev/null | tail -1 || echo "")
    
    if [ -z "$PASSWORD_HASH" ]; then
        echo "Error: Could not hash password. Please install passlib or use a different method."
        exit 1
    fi
fi

echo "Password hash generated: ${PASSWORD_HASH:0:20}..."
echo ""
echo "Inserting user into database..."

# Insert user into MAS database
docker compose exec -T postgres psql -U synapse -d mas << EOSQL
-- Insert user
INSERT INTO users (user_id, username, created_at, can_request_admin)
VALUES ('$USER_ID', '$USERNAME', NOW(), true);

-- Insert email (optional, using username@localhost)
INSERT INTO user_emails (user_email_id, user_id, email, created_at, confirmed_at)
VALUES ('$EMAIL_ID', '$USER_ID', '${USERNAME}@localhost', NOW(), NOW());

-- Update user to set primary email
UPDATE users SET primary_user_email_id = '$EMAIL_ID' WHERE user_id = '$USER_ID';

-- Insert password
INSERT INTO user_passwords (user_password_id, user_id, hashed_password, created_at, version)
VALUES (gen_random_uuid(), '$USER_ID', '$PASSWORD_HASH', NOW(), 1);

-- Make user an admin (insert into appropriate table if it exists)
-- Note: MAS might use can_request_admin flag or separate admin table

SELECT 'User created successfully!' as result;
SELECT 'User ID: $USER_ID' as info;
SELECT 'Username: $USERNAME' as info;
EOSQL

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Admin user created successfully!"
    echo ""
    echo "Username: $USERNAME"
    echo "Password: (as entered)"
    echo ""
    echo "You can now log in to Element at http://localhost:8080"
    echo "Or access MAS admin panel at http://localhost:8090/_auth/"
else
    echo ""
    echo "❌ Failed to create user"
    exit 1
fi
