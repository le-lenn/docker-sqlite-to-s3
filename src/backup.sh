#! /bin/sh

set -eu
set -o pipefail

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/env.sh"

timestamp=$(date +"%Y%m%d%H%M%S")

echo "Backing up $DATABASE_PATH to temporary file..."

# Use SQLite online backup API to copy to a temporary path
if ! sqlite3 "$DATABASE_PATH" <<SQL
.timeout ${SQLITE_TIMEOUT_MS}
.backup '$BACKUP_PATH'
SQL
then
  echo "Failed to backup $DATABASE_PATH to $BACKUP_PATH"
  exit 1
fi

# Optional: encrypt before upload
UPLOAD_SOURCE="$BACKUP_PATH"
if [ -n "${ENCRYPTION_KEY:-}" ]; then
  echo "Encrypting backup before upload..."
  if openssl enc -aes-256-cbc -pbkdf2 -salt -iter 100000 -pass env:ENCRYPTION_KEY -in "$BACKUP_PATH" -out "${BACKUP_PATH}.enc"; then
    UPLOAD_SOURCE="${BACKUP_PATH}.enc"
    rm -f "$BACKUP_PATH"
  else
    echo "Encryption failed"
    rm -f "${BACKUP_PATH}.enc" || true
    exit 1
  fi
fi

s3_uri="s3://${S3_BUCKET}/${S3_PREFIX}${timestamp}.bak"

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
  curl -fsSL -X POST "${POST_WEBHOOK_URL}" >/dev/null 2>&1 || echo "Webhook trigger failed"
fi

# Cleanup local temp files
rm -f "$BACKUP_PATH" "${BACKUP_PATH}.enc" 2>/dev/null || true

echo "Backup complete."

