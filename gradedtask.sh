#!/usr/bin/env bash
# Simple Automated Backup System (Linux)
# Features: backup + verify + cleanup + logging

set -euo pipefail
LOG_FILE="backup.log"
DEST="./backups"
KEEP_DAYS=7

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

usage() {
  echo "Usage: $0 <folder_to_backup>"
  exit 1
}

[ $# -lt 1 ] && usage
SRC="$1"

if [ ! -d "$SRC" ]; then
  log "ERROR: Source folder not found: $SRC"
  exit 1
fi

mkdir -p "$DEST"

# Timestamp + names
TS=$(date '+%Y-%m-%d-%H%M')
BACKUP="$DEST/backup-$TS.tar.gz"
CHECKSUM="$BACKUP.sha256"

log "Starting backup of $SRC"
tar --exclude='.git' --exclude='node_modules' --exclude='.cache' -czf "$BACKUP" -C "$(dirname "$SRC")" "$(basename "$SRC")"
sha256sum "$BACKUP" | awk '{print $1}' > "$CHECKSUM"
log "Backup created: $(basename "$BACKUP")"

# Verify
log "Verifying backup..."
CHECK=$(sha256sum "$BACKUP" | awk '{print $1}')
SAVED=$(cat "$CHECKSUM")
if [ "$CHECK" != "$SAVED" ]; then
  log "ERROR: Checksum mismatch!"
  exit 1
else
  log "Verification successful."
fi

# Delete backups older than KEEP_DAYS
log "Cleaning up backups older than $KEEP_DAYS days..."
find "$DEST" -name "backup-*.tar.gz" -mtime +"$KEEP_DAYS" -exec rm -f {} {}.sha256 \;
log "Cleanup done."
log "SUCCESS: Backup complete ✅"
