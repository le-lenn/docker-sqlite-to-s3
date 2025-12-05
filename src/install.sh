#! /bin/sh

set -eux
set -o pipefail

apk update

apk add --no-cache sqlite aws-cli age curl ca-certificates

# Install go-cron like the postgres project
ARCH="${TARGETARCH:-amd64}"
case "$ARCH" in
  amd64|x86_64) GOCRON_ARCH="amd64" ;;
  arm64|aarch64) GOCRON_ARCH="arm64" ;;
  arm) GOCRON_ARCH="arm" ;;
  *) GOCRON_ARCH="$ARCH" ;;
esac

curl -fsSL -o /tmp/go-cron.tgz "https://github.com/ivoronin/go-cron/releases/download/v0.0.5/go-cron_0.0.5_linux_${GOCRON_ARCH}.tar.gz"
tar -C /usr/local/bin -xzf /tmp/go-cron.tgz go-cron
chmod u+x /usr/local/bin/go-cron
rm -f /tmp/go-cron.tgz

# Cleanup
rm -rf /var/cache/apk/*
