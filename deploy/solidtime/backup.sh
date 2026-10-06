#!/usr/bin/env bash
# Nightly backup of the solidtime database and uploaded files.
# Cron (as root): 30 2 * * * /opt/solidtime/backup.sh >> /var/log/solidtime-backup.log 2>&1
set -euo pipefail
umask 077  # dumps contain all user data — root-only

cd "$(dirname "$0")"
set -a; source .env; set +a

BACKUP_DIR="${BACKUP_DIR:-/opt/backups/solidtime}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
STAMP="$(date +%F_%H%M)"
mkdir -p "$BACKUP_DIR"

docker compose exec -T database pg_dump -U "$DB_USERNAME" -d "$DB_DATABASE" --format=custom \
    > "$BACKUP_DIR/db_$STAMP.dump"
tar -czf "$BACKUP_DIR/files_$STAMP.tar.gz" app-storage

find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -delete

# Off-server copy (Hetzner Storage Box). Set STORAGE_BOX, e.g. u123456@u123456.your-storagebox.de
if [[ -n "${STORAGE_BOX:-}" ]]; then
    rsync -a --delete -e "ssh -p 23" "$BACKUP_DIR/" "$STORAGE_BOX:solidtime/"
fi

echo "$(date -Is) backup ok: $STAMP"
