#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck source=backup.config

set -euo pipefail
IFS=$'\n\t'

# Helpful shell options
shopt -s nullglob   # makes globs expand to empty array if no match

# Load Configuration
CONFIG_FILE="./backup.config"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Configuration file not found: $CONFIG_FILE" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Ensure required config variables exist (provide defaults if necessary)
: "${BACKUP_DESTINATION:="./backupfiles"}"
: "${LOG_FILE:="./backup.log"}"
: "${LOCK_FILE:="./backup.lock"}"
: "${DAILY_KEEP:=7}"
: "${WEEKLY_KEEP:=4}"
: "${MONTHLY_KEEP:=3}"
: "${EXCLUDE_PATTERNS:=""}"
: "${EMAIL_FILE:="./email.txt"}"

# Ensure backup destination exists
mkdir -p "$BACKUP_DESTINATION"

# Logging function
log() {
  local msg="$1"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" | tee -a "$LOG_FILE"
}

# Cleanup lock file on exit
cleanup() {
  rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# Prevent multiple runs
if [[ -f "$LOCK_FILE" ]]; then
  log "ERROR: Another backup process is already running (lock: $LOCK_FILE). Exiting."
  exit 1
fi
# Create lock file
: > "$LOCK_FILE"

# Disk space check
check_space() {
  local available required
  # available in KB
  available=$(df --output=avail -k "$BACKUP_DESTINATION" 2>/dev/null | tail -n 1 | tr -d '[:space:]' || echo "0")
  required=$(du -sk "$SOURCE_DIR" 2>/dev/null | awk '{print $1}' || echo "0")
  # Fallback to success if values are not numeric
  if ! [[ "$available" =~ ^[0-9]+$ && "$required" =~ ^[0-9]+$ ]]; then
    log "WARN: Unable to determine disk space reliably. Continuing."
    return 0
  fi
  if (( available < required )); then
    log "ERROR: Not enough disk space for backup. Available=${available}KB Required=${required}KB"
    exit 1
  fi
}

# Simulated email (writes into a file)
send_email() {
  local subject="$1"
  local message="$2"
  {
    printf '---\nSubject: %s\nDate: %s\n%s\n\n' "$subject" "$(date '+%Y-%m-%d %H:%M:%S')" "$message"
  } >> "$EMAIL_FILE"
  log "Email simulated: $subject"
}

# Verify backup using sha256sum
verify_backup() {
  local checksum_file="$1.sha256"
  pushd "$BACKUP_DESTINATION" >/dev/null || return 1
  if [[ ! -f "$checksum_file" ]]; then
    log "ERROR: Checksum file not found: $checksum_file"
    popd >/dev/null || true
    return 1
  fi

  if sha256sum -c "$checksum_file" >> "$LOG_FILE" 2>&1; then
    log "INFO: Checksum verified successfully for $1"
    send_email "Backup Success" "Backup $1 verified successfully."
    popd >/dev/null || true
    return 0
  else
    log "ERROR: Backup verification failed for $1"
    send_email "Backup Verification Failed" "Checksum failed for $1"
    popd >/dev/null || true
    return 2
  fi
}

# Delete old backups according to rotation policy
delete_old_backups() {
  pushd "$BACKUP_DESTINATION" >/dev/null || return 1
  log "Cleaning old backups..."

  # Use mapfile to safely build arrays (avoid word splitting)
  mapfile -t daily_backups < <(ls -1t backup-*.tar.gz 2>/dev/null | head -n "$DAILY_KEEP" || true)
  mapfile -t weekly_backups < <(find . -maxdepth 1 -type f -name "backup-*.tar.gz" -mtime -28 -printf "%f\n" 2>/dev/null | sort -r | head -n "$WEEKLY_KEEP" || true)
  mapfile -t monthly_backups < <(find . -maxdepth 1 -type f -name "backup-*.tar.gz" -mtime +28 -printf "%f\n" 2>/dev/null | sort -r | head -n "$MONTHLY_KEEP" || true)

  # Build keep list (may include duplicates)
  keep_list=()
  keep_list+=("${daily_backups[@]}")
  keep_list+=("${weekly_backups[@]}")
  keep_list+=("${monthly_backups[@]}")

  # For faster membership test, we build a single string
  keep_joined=" ${keep_list[*]} "

  # Iterate backups (nullglob ensures no-literal-glob)
  for file in backup-*.tar.gz; do
    # Skip if not a file (safety)
    [[ -f "$file" ]] || continue

    # Use =~ without quoting RHS to allow pattern match
    if [[ ! $keep_joined =~ $file ]]; then
      rm -f -- "$file" "$file.sha256"
      log "Deleted old backup: $file"
    fi
  done

  popd >/dev/null || true
}

# Restore a backup
restore_backup() {
  local backup_file="$1"
  local restore_dir="$2"

  if [[ -z "$backup_file" || -z "$restore_dir" ]]; then
    echo "Usage: $0 --restore <backup_file> <restore_dir>" >&2
    exit 1
  fi

  if [[ ! -f "$BACKUP_DESTINATION/$backup_file" ]]; then
    echo "Backup file not found: $BACKUP_DESTINATION/$backup_file" >&2
    exit 1
  fi

  mkdir -p "$restore_dir"
  if tar -xzf "$BACKUP_DESTINATION/$backup_file" -C "$restore_dir"; then
    log "Restored backup $backup_file to $restore_dir"
  else
    log "ERROR: Failed to restore $backup_file"
    exit 1
  fi
}

# List backups
list_backups() {
  log "Available Backups in $BACKUP_DESTINATION:"
  if ! ls -lh "$BACKUP_DESTINATION"/backup-*.tar.gz 2>/dev/null | sed -n '1,200p'; then
    echo "No backups found." >&2
  fi
}

# Create backup (full or incremental)
create_backup() {
  local timestamp backup_name checksum_file snar_file
  timestamp=$(date +'%Y-%m-%d-%H%M')
  backup_name="backup-$timestamp.tar.gz"
  checksum_file="$backup_name.sha256"
  snar_file="$BACKUP_DESTINATION/backup.snar"

  log "INFO: Starting backup of $SOURCE_DIR"

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log "[DRY RUN] Would back up: $SOURCE_DIR -> $BACKUP_DESTINATION"
    return 0
  fi

  mkdir -p "$BACKUP_DESTINATION"
  check_space

  # Build exclude arguments
  local excludes=()
  if [[ -n "${EXCLUDE_PATTERNS:-}" ]]; then
    IFS=',' read -ra patterns <<< "$EXCLUDE_PATTERNS"
    for pattern in "${patterns[@]}"; do
      pattern="${pattern#"${pattern%%[![:space:]]*}"}"   # trim leading spaces
      pattern="${pattern%"${pattern##*[![:space:]]}"}"   # trim trailing spaces
      [[ -n "$pattern" ]] || continue
      excludes+=(--exclude="$pattern")
    done
  fi

  if [[ -f "$snar_file" ]]; then
    log "INFO: Performing incremental backup (snapshot: $snar_file)"
  else
    log "INFO: Performing first full backup"
  fi

  # Create the tarball; check exit code directly
  if ! tar --listed-incremental="$snar_file" -czf "$BACKUP_DESTINATION/$backup_name" "${excludes[@]}" "$SOURCE_DIR" 2>>"$LOG_FILE"; then
    log "ERROR: Failed to create backup $backup_name"
    send_email "Backup Failed" "Backup of $SOURCE_DIR failed at $(date '+%Y-%m-%d %H:%M:%S')"
    exit 1
  fi

  # Create checksum
  if sha256sum "$BACKUP_DESTINATION/$backup_name" > "$BACKUP_DESTINATION/$checksum_file"; then
    log "SUCCESS: Backup created: $backup_name"
  else
    log "ERROR: Failed to create checksum for $backup_name"
    exit 1
  fi

  # Verify checksum
  verify_backup "$backup_name"
}

# ---------------------------
# Command-line parsing
# ---------------------------
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  SOURCE_DIR="${2:-}"
elif [[ "${1:-}" == "--restore" ]]; then
  BACKUP_FILE="${2:-}"
  RESTORE_DIR="${3:-}"
  restore_backup "$BACKUP_FILE" "$RESTORE_DIR"
  exit 0
elif [[ "${1:-}" == "--list" ]]; then
  list_backups
  exit 0
else
  DRY_RUN=false
  SOURCE_DIR="${1:-}"
fi

if [[ -z "${SOURCE_DIR:-}" ]]; then
  echo "Usage: $0 [--dry-run] <source_directory>" >&2
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

# MAIN
create_backup
delete_old_backups

# Lock file removal happens via trap cleanup()
exit 0
