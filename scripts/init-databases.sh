#!/bin/bash
set -e

# Create Synapse and MAS databases
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE synapse;
    CREATE DATABASE mas;
    GRANT ALL PRIVILEGES ON DATABASE synapse TO "$POSTGRES_USER";
    GRANT ALL PRIVILEGES ON DATABASE mas TO "$POSTGRES_USER";
EOSQL
