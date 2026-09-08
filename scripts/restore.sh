#!/bin/bash
# =============================================================================
# Matrix Server Restore Script
# Restores Postgres + media store from an OCI Object Storage backup.
#
# Usage:
#   ./restore.sh                  # restore from the most recent backup
#   ./restore.sh 20260301-100000  # restore from the most recent backup AT OR BEFORE this time
#   ./restore.sh --list           # list all available backups
# =============================================================================

set -e

OCI="/home/ubuntu/bin/oci"
APP_DIR="/opt/matrix/app"
OCI_BUCKET="matrix-backups"
RESTORE_DIR="/tmp/matrix-restore"

# ── List all available backups ────────────────────────────────────────────────
list_backups() {
  $OCI os object list \
    --auth instance_principal \
    --bucket-name "$OCI_BUCKET" \
    --prefix "backups/" \
    --output json --all 2>/dev/null | \
  python3 -c "
import sys, json
objs = json.load(sys.stdin).get('data', [])
dates = sorted(set(o['name'].split('/')[1] for o in objs if len(o['name'].split('/')) > 2), reverse=True)
for d in dates:
    print(' ', d)
"
}

# ── Find the best backup for a given cutoff ───────────────────────────────────
# Returns the most recent backup at or before the given cutoff timestamp.
# Cutoff format: YYYYMMDD-HHMMSS (or YYYYMMDD, which compares by date prefix).
find_backup() {
  local cutoff="${1:-99999999-999999}"  # default: any time (picks newest)
  $OCI os object list \
    --auth instance_principal \
    --bucket-name "$OCI_BUCKET" \
    --prefix "backups/" \
    --output json --all 2>/dev/null | \
  python3 -c "
import sys, json
objs = json.load(sys.stdin).get('data', [])
cutoff = '$cutoff'.replace('-', '')  # normalize: strip hyphens for comparison
dates = sorted(set(o['name'].split('/')[1] for o in objs if len(o['name'].split('/')) > 2), reverse=True)
# Find the most recent backup whose timestamp (stripped of hyphens) <= cutoff
for d in dates:
    if d.replace('-', '') <= cutoff:
        print(d)
        sys.exit(0)
print('NONE')
"
}

# ── Parse args ────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--list" ]; then
  echo "Available backups (newest first):"
  list_backups
  exit 0
fi

CUTOFF="${1:-}"  # empty = most recent

# Determine which backup to restore
if [ -n "$CUTOFF" ]; then
  echo "Finding most recent backup at or before: $CUTOFF"
  BACKUP_DATE=$(find_backup "$CUTOFF")
else
  echo "Finding most recent backup..."
  BACKUP_DATE=$(find_backup)
fi

if [ "$BACKUP_DATE" = "NONE" ] || [ -z "$BACKUP_DATE" ]; then
  echo "[ERROR] No backup found$([ -n "$CUTOFF" ] && echo " at or before $CUTOFF" || echo "")."
  echo "Available backups:"
  list_backups
  exit 1
fi

SELECTED="$BACKUP_DATE"
echo "Selected backup: $SELECTED"

# ── Confirm ───────────────────────────────────────────────────────────────────
echo ""
read -p "[WARN] This will STOP all containers and overwrite the database. Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

rm -rf "$RESTORE_DIR"
mkdir -p "$RESTORE_DIR"
cd "$APP_DIR"

# ── Download from OCI ─────────────────────────────────────────────────────────
echo ""
echo "Downloading backup from OCI..."
$OCI os object bulk-download \
  --auth instance_principal \
  --bucket-name "$OCI_BUCKET" \
  --download-dir "$RESTORE_DIR" \
  --object-prefix "backups/$SELECTED/" \
  --overwrite \
  --output none
# Flatten — files land in $RESTORE_DIR/backups/$SELECTED/
mv "$RESTORE_DIR/backups/$SELECTED/"* "$RESTORE_DIR/" 2>/dev/null || true

# ── Stop containers ───────────────────────────────────────────────────────────
echo ""
echo "Stopping Synapse and workers..."
docker compose stop synapse \
  synapse-generic-worker-1 \
  synapse-generic-worker-2 \
  synapse-federation-sender \
  synapse-media-repository 2>/dev/null || docker compose stop synapse

# ── Restore Postgres ──────────────────────────────────────────────────────────
echo "Restoring Postgres..."
# Drop and recreate database to ensure clean state
docker compose exec -T postgres psql -U synapse -d postgres -c \
  "DROP DATABASE IF EXISTS synapse; CREATE DATABASE synapse OWNER synapse;"
gunzip -c "$RESTORE_DIR/postgres.sql.gz" | \
  docker compose exec -T postgres psql -U synapse -d synapse -q
echo "  [OK] Postgres restored"

# ── Restore media store ───────────────────────────────────────────────────────
if [ -f "$RESTORE_DIR/media.tar.gz" ]; then
  echo "Restoring media repository..."
  docker compose run --rm -v synapse_media:/data/media alpine \
    sh -c "rm -rf /data/media/* && tar -xzf - -C /data/media" < "$RESTORE_DIR/media.tar.gz"
  echo "  [OK] Media restored"
fi

# ── Restart everything ────────────────────────────────────────────────────────
echo "Starting all containers..."
docker compose up -d

rm -rf "$RESTORE_DIR"
echo "=== Restore complete from backup: $BACKUP_DATE ==="
echo "Verify with: docker compose ps"
