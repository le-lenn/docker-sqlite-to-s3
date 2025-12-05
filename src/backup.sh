#! /bin/sh

set -eu
set -o pipefail

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/env.sh"

timestamp=$(date +"%Y_%m_%d_%H%M")

# Debug context
log_debug "Script DIR=${DIR}"
log_debug "Working directory=$(pwd)"
log_debug "Will back up from DATABASE_PATH=${DATABASE_PATH}"
log_debug "Temporary BACKUP_PATH=${BACKUP_PATH}"
if [ -e "${DATABASE_PATH}" ]; then
  log_debug "Database file exists at ${DATABASE_PATH}"
else
  echo "Database file does not exist at ${DATABASE_PATH}. Aborting backup."
  exit 1
fi

echo "Backing up $DATABASE_PATH to temporary file..."

# Use SQLite online backup API to copy to a temporary path
log_debug "Running sqlite3 .backup with timeout ${SQLITE_TIMEOUT_MS}ms"
if ! sqlite3 "$DATABASE_PATH" <<SQL
.timeout ${SQLITE_TIMEOUT_MS}
.backup '$BACKUP_PATH'
SQL
then
  echo "Failed to backup $DATABASE_PATH to $BACKUP_PATH"
  exit 1
fi

echo "Encrypting backup with age (passphrase) before upload..."
UPLOAD_SOURCE="${BACKUP_PATH}.age"
if [ -n "${AGE_PASSPHRASE:-}" ]; then
  if {
    printf '%s\n' "$AGE_PASSPHRASE";
    printf '%s\n' "$AGE_PASSPHRASE";
  } | age -p -o "$UPLOAD_SOURCE" "$BACKUP_PATH"; then
    rm -f "$BACKUP_PATH"
    log_debug "Age passphrase encryption succeeded; upload source=${UPLOAD_SOURCE}"
  else
    echo "Age encryption failed"
    rm -f "$UPLOAD_SOURCE" || true
    exit 1
  fi
else
  echo "You must set AGE_PASSPHRASE for encryption."
  rm -f "$BACKUP_PATH" || true
  exit 1
fi

s3_uri="s3://${S3_BUCKET}/${S3_PREFIX}${timestamp}.age"

log_debug "AWS CLI args: ${aws_args}"
if [ -n "${S3_ENDPOINT:-}" ]; then
  log_debug "Using S3 endpoint: ${S3_ENDPOINT}"
fi
log_debug "Backup file size: $(wc -c < "${UPLOAD_SOURCE}" 2>/dev/null || echo unknown) bytes"

echo "Uploading backup to $s3_uri..."
if aws $aws_args s3 cp "$UPLOAD_SOURCE" "$s3_uri"; then
  echo "Backup uploaded to $s3_uri"
else
  echo "Backup upload failed"
  exit 1
fi

# Optional: webhook after successful backup
if [ -n "${POST_WEBHOOK_URL:-}" ]; then
  echo "Triggering POST webhook: ${POST_WEBHOOK_URL}"
  if [ "${LOG_LEVEL}" = "debug" ]; then
    curl -fsS -X POST "${POST_WEBHOOK_URL}" || echo "Webhook trigger failed"
  else
    curl -fsSL -X POST "${POST_WEBHOOK_URL}" >/dev/null 2>&1 || echo "Webhook trigger failed"
  fi
fi

# Cleanup local temp files
rm -f "$BACKUP_PATH" "$UPLOAD_SOURCE" 2>/dev/null || true

echo "Backup complete."

log_debug "Cleanup complete."
