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
  echo "❌ No backup found$([ -n "$CUTOFF" ] && echo " at or before $CUTOFF" || echo "")."
  echo "Available backups:"
  list_backups
  exit 1
fi

echo "Selected backup: $BACKUP_DATE"

# ── Confirm ───────────────────────────────────────────────────────────────────
read -p "⚠️  This will STOP all containers and overwrite the database. Continue? (yes/no): " CONFIRM
[ "$CONFIRM" != "yes" ] && { echo "Aborted."; exit 1; }

mkdir -p "$RESTORE_DIR"
cd "$APP_DIR"

# ── Download from OCI ─────────────────────────────────────────────────────────
echo "Downloading backup '$BACKUP_DATE' from OCI..."
$OCI os object bulk-download \
  --auth instance_principal \
  --bucket-name "$OCI_BUCKET" \
  --download-dir "$RESTORE_DIR" \
  --object-prefix "backups/$BACKUP_DATE/"

# ── Stop containers ───────────────────────────────────────────────────────────
echo "Stopping containers..."
docker compose stop

# ── Restore Postgres ──────────────────────────────────────────────────────────
echo "Restoring PostgreSQL..."
docker compose start postgres
sleep 5

docker compose exec -T postgres psql -U postgres -c "DROP DATABASE IF EXISTS synapse;" || true
docker compose exec -T postgres psql -U postgres -c "DROP DATABASE IF EXISTS mas;" || true
gunzip -c "$RESTORE_DIR/backups/$BACKUP_DATE/postgres.sql.gz" | \
  docker compose exec -T postgres psql -U postgres
echo "  ✓ Postgres restored"

# ── Restore media store ───────────────────────────────────────────────────────
MEDIA_BACKUP="$RESTORE_DIR/backups/$BACKUP_DATE/media.tar.gz"
if [ -f "$MEDIA_BACKUP" ]; then
  echo "Restoring media store..."
  SYNAPSE_VOL=$(docker volume inspect app_synapse_data --format '{{.Mountpoint}}')
  sudo rm -rf "$SYNAPSE_VOL/media_store"
  sudo tar -xzf "$MEDIA_BACKUP" -C "$SYNAPSE_VOL"
  echo "  ✓ Media restored"
fi

# ── Restart everything ────────────────────────────────────────────────────────
echo "Starting all containers..."
docker compose up -d

rm -rf "$RESTORE_DIR"
echo "=== Restore complete from backup: $BACKUP_DATE ==="
echo "Verify with: docker compose ps"
