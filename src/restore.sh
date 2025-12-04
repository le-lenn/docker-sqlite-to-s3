#! /bin/sh

set -u
set -o pipefail

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/env.sh"

s3_uri_base="s3://${S3_BUCKET}/${S3_PREFIX}"

# Debug context
log_debug "Script DIR=${DIR}"
log_debug "Working directory=$(pwd)"
log_debug "Target DATABASE_PATH=${DATABASE_PATH}"
log_debug "Temporary BACKUP_PATH=${BACKUP_PATH}"
log_debug "S3 base URI=${s3_uri_base}"
log_debug "AWS CLI args: ${aws_args}"
if [ -n "${S3_ENDPOINT:-}" ]; then
  log_debug "Using S3 endpoint: ${S3_ENDPOINT}"
fi

# Determine which object to restore: explicit timestamp or find the latest
file_key=""
if [ $# -ge 1 ] && [ -n "$1" ]; then
  ts="$1"
  file_key="${ts}.bak"
  log_debug "Using specified timestamp: ${ts} (key=${file_key})"
else
  echo "Finding latest backup in $s3_uri_base..."
  # List objects under the prefix, sort and pick the last (newest)
  file_key=$(aws $aws_args s3 ls "$s3_uri_base" \
    | awk '{print $4}' \
    | grep -E '\.bak$' \
    | sort \
    | tail -n 1)
  if [ -z "$file_key" ]; then
    echo "No backups found under $s3_uri_base"
    exit 1
  fi
  log_debug "Selected latest backup key: ${file_key}"
fi

echo "Fetching backup from S3: ${s3_uri_base}${file_key}"

tmp_file="${BACKUP_PATH}"
rm -f "$tmp_file" "$tmp_file.decrypted" 2>/dev/null || true

aws $aws_args s3 cp "${s3_uri_base}${file_key}" "$tmp_file"
log_debug "Downloaded to ${tmp_file}"

# If the file is encrypted (OpenSSL salted), require ENCRYPTION_KEY and decrypt
RESTORE_SOURCE="$tmp_file"
if is_encrypted_file "$tmp_file"; then
  echo "Downloaded backup appears to be encrypted."
  if [ -z "${ENCRYPTION_KEY:-}" ]; then
    echo "Error: ENCRYPTION_KEY must be set to restore encrypted backups."
    exit 1
  fi
  if openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass env:ENCRYPTION_KEY -in "$tmp_file" -out "${tmp_file}.decrypted"; then
    RESTORE_SOURCE="${tmp_file}.decrypted"
    log_debug "Decryption succeeded; restore source=${RESTORE_SOURCE}"
  else
    echo "Decryption failed"
    exit 1
  fi
else
  log_debug "File is not encrypted; restore source=${RESTORE_SOURCE}"
fi

echo "Restoring database at $DATABASE_PATH ..."
log_debug "Running sqlite3 .restore with timeout ${SQLITE_TIMEOUT_MS}ms"

# Move current DB aside and remove SHM/WAL if present
[ -e "$DATABASE_PATH" ] && mv "$DATABASE_PATH" "${DATABASE_PATH}.old" || true
rm -f "${DATABASE_PATH}-wal" "${DATABASE_PATH}-shm" 2>/dev/null || true

if sqlite3 "$DATABASE_PATH" <<SQL
.timeout ${SQLITE_TIMEOUT_MS}
.restore '$RESTORE_SOURCE'
SQL
then
  echo "Restore complete."
  rm -f "${DATABASE_PATH}.old" 2>/dev/null || true
  rm -f "$tmp_file" "${tmp_file}.decrypted" 2>/dev/null || true
  log_debug "Cleanup complete; restored ${DATABASE_PATH}"
else
  echo "Restore failed"
  if [ -e "${DATABASE_PATH}.old" ]; then
    echo "Reverting to previous database file."
    mv "${DATABASE_PATH}.old" "$DATABASE_PATH"
  fi
  rm -f "$tmp_file" "${tmp_file}.decrypted" 2>/dev/null || true
  exit 1
fi
