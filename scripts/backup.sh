#!/bin/bash
# =============================================================================
# Matrix Server Backup Script
# Ships compressed Postgres + media store to Oracle Object Storage (OCI)
# =============================================================================
# Prerequisites:
#   - OCI CLI installed on server: bash -c "$(curl -fsSL https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
#   - OCI CLI configured: oci setup config
#   - OCI bucket created: oci os bucket create --name matrix-backups --compartment-id <your-compartment-id>
#
# Setup cron (daily at 3am):
#   chmod +x /opt/matrix/scripts/backup.sh
#   crontab -e  →  0 3 * * * /opt/matrix/scripts/backup.sh >> /var/log/matrix-backup.log 2>&1
# =============================================================================

set -e

APP_DIR="/opt/matrix/app"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/tmp/matrix-backup-$DATE"
OCI="/home/ubuntu/bin/oci"
OCI_BUCKET="matrix-backups"
RETAIN_DAYS=30

echo "=== Matrix Backup: $DATE ==="
mkdir -p "$BACKUP_DIR"
cd "$APP_DIR"

# 1. Postgres full dump (all databases: synapse + mas)
echo "Dumping PostgreSQL..."
docker compose exec -T postgres pg_dumpall -U postgres | gzip > "$BACKUP_DIR/postgres.sql.gz"
echo "  ✓ Postgres: $(du -sh $BACKUP_DIR/postgres.sql.gz | cut -f1)"

# 2. Synapse media store
echo "Archiving media store..."
SYNAPSE_VOL="app_synapse_data"
# Verify the volume actually exists
if docker volume inspect "$SYNAPSE_VOL" >/dev/null 2>&1; then
  # Spin up a temporary container attached to the volume to tar the media store directly
  # avoiding any brittle host-path dependencies
  docker run --rm -v "$SYNAPSE_VOL":/data \
    -v "$BACKUP_DIR":/backup ubuntu:latest \
    bash -c "if [ -d /data/media_store ]; then tar -czf /backup/media.tar.gz -C /data media_store; fi"
  
  if [ -f "$BACKUP_DIR/media.tar.gz" ]; then
    echo "  ✓ Media: $(du -sh $BACKUP_DIR/media.tar.gz | cut -f1)"
  else
    echo "  ⚠ No media_store found inside volume, skipping"
  fi
else
  echo "  ⚠ Volume $SYNAPSE_VOL not found, skipping"
fi

# 3. Config snapshot (no secrets — those live in GitHub)
tar -czf "$BACKUP_DIR/config.tar.gz" \
  -C "$APP_DIR" \
  nginx/nginx.conf docker-compose.yml synapse/homeserver.yaml.template element/config.json \
  2>/dev/null || true
echo "  ✓ Config archived"

# 4. Upload to Oracle Object Storage (using Instance Principal auth — no credentials file needed)
echo "Uploading to OCI bucket '$OCI_BUCKET'..."
$OCI os object bulk-upload \
  --auth instance_principal \
  --bucket-name "$OCI_BUCKET" \
  --src-dir "$BACKUP_DIR" \
  --object-prefix "backups/$DATE/" \
  --overwrite
echo "  ✓ Uploaded: backups/$DATE/"

# 5. Prune OCI backups older than RETAIN_DAYS (lifecycle policy also handles this)
CUTOFF=$(date -d "$RETAIN_DAYS days ago" +%Y%m%d 2>/dev/null || date -v-${RETAIN_DAYS}d +%Y%m%d)
echo "Pruning backups older than $CUTOFF..."
$OCI os object list \
  --auth instance_principal \
  --bucket-name "$OCI_BUCKET" \
  --prefix "backups/" \
  --output json --all | \
  python3 -c "
import sys, json
objs = json.load(sys.stdin).get('data', [])
cutoff = '$CUTOFF'
for o in objs:
    name = o.get('name', '')
    date_part = name.split('/')[1][:8] if '/' in name else ''
    if date_part and date_part < cutoff:
        print(name)
" | while read -r obj; do
    oci os object delete --bucket-name "$OCI_BUCKET" --object-name "$obj" --force
    echo "  Deleted: $obj"
  done

# 6. Cleanup local temp
rm -rf "$BACKUP_DIR"
echo "=== Backup complete: $(date) ==="
