#!/bin/bash

# Script to easily create Matrix users

echo "👤 Create Matrix User"
echo "===================="
echo ""

# Check if Synapse is running
if ! docker compose ps synapse | grep -q "Up"; then
    echo "❌ Error: Synapse is not running!"
    echo "Start it with: docker compose up -d"
    exit 1
fi

echo "Creating a new Matrix user..."
echo ""

# Ask if admin
read -p "Should this user be an admin? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Creating admin user..."
    docker compose exec synapse register_new_matrix_user http://localhost:8008 -c /data/homeserver.yaml -a
else
    echo "Creating regular user..."
    docker compose exec synapse register_new_matrix_user http://localhost:8008 -c /data/homeserver.yaml
fi

echo ""
echo "✅ User created successfully!"
echo ""
echo "You can now sign in at: http://localhost:8080"
echo "Your username will be: @username:localhost"
echo ""
