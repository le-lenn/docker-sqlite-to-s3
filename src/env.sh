#! /bin/sh

set -eu

# Validate required environment variables and normalize optional ones.

# Required: S3 bucket
if [ -z "${S3_BUCKET:-}" ]; then
  echo "You need to set the S3_BUCKET environment variable."
  exit 1
fi

# Required: path to the SQLite database file inside the container
if [ -z "${DATABASE_PATH:-}" ]; then
  echo "You need to set the DATABASE_PATH environment variable."
  exit 1
fi

# Key prefix within the bucket (optional). Ensure trailing slash if set.
if [ -n "${S3_PREFIX:-}" ]; then
  case "$S3_PREFIX" in
    */) : ;;
    *) S3_PREFIX="${S3_PREFIX}/" ;;
  esac
else
  S3_PREFIX=""
fi

# Logging: allow opt-in verbose output for troubleshooting
# Accepted values: "info" (default) or "debug"
LOG_LEVEL="${LOG_LEVEL:-info}"

# Debug logger helper
log_debug() {
  if [ "${LOG_LEVEL}" = "debug" ]; then
    # shellcheck disable=SC2145
    echo "[debug] $@"
  fi
}

# Optional: S3-compatible endpoint override for aws-cli
if [ -z "${S3_ENDPOINT:-}" ]; then
  aws_args=""
else
  aws_args="--endpoint-url $S3_ENDPOINT"
fi

# Optional: support S3_* credential variable names like the postgres project
if [ -n "${S3_ACCESS_KEY_ID:-}" ] && [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
  export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
fi
if [ -n "${S3_SECRET_ACCESS_KEY:-}" ] && [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
fi
if [ -n "${S3_REGION:-}" ] && [ -z "${AWS_DEFAULT_REGION:-}" ]; then
  export AWS_DEFAULT_REGION="$S3_REGION"
fi

# Derived/default variables
BACKUP_PATH="${BACKUP_PATH:-${DATABASE_PATH}.bak}"
SQLITE_TIMEOUT_MS="${SQLITE_TIMEOUT_MS:-10000}"

# Helper: check if a file has the OpenSSL salted header (our encryption format)
is_encrypted_file() {
  file="$1"
  [ -f "$file" ] || return 1
  head -c 8 "$file" 2>/dev/null | grep -q '^Salted__$' 2>/dev/null
}

# Emit environment context in debug mode to help with path issues
if [ "${LOG_LEVEL}" = "debug" ]; then
  log_debug "LOG_LEVEL=${LOG_LEVEL}"
  log_debug "DATABASE_PATH=${DATABASE_PATH}"
  log_debug "BACKUP_PATH=${BACKUP_PATH}"
  log_debug "S3_BUCKET=${S3_BUCKET}"
  log_debug "S3_PREFIX=${S3_PREFIX}"
  if [ -n "${S3_ENDPOINT:-}" ]; then
    log_debug "S3_ENDPOINT=${S3_ENDPOINT}"
  fi
  if [ -n "${AWS_DEFAULT_REGION:-}" ]; then
    log_debug "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"
  fi
  log_debug "SQLITE_TIMEOUT_MS=${SQLITE_TIMEOUT_MS}"
fi
