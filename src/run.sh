#! /bin/sh

set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/env.sh"

# Optional: force AWS S3 signature v4
if [ "${S3_S3V4:-no}" = "yes" ]; then
  aws configure set default.s3.signature_version s3v4 >/dev/null 2>&1 || true
fi

# Run an immediate backup if no schedule is provided; otherwise run via go-cron
if [ -z "${SCHEDULE:-}" ]; then
  exec sh "$DIR/backup.sh"
else
  exec go-cron "$SCHEDULE" /bin/sh "$DIR/backup.sh"
fi
