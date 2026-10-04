#!/usr/bin/env bash
# Runs a one-off pocketbase command on the VPS with the same folders and encryption key as the
# running server. Use it with sudo, for example:
#
#   sudo /opt/letterman/pb.sh superuser upsert you@example.com 'a-long-password'
#
# (See FIRST_SETUP.md, step B8.)
set -euo pipefail

set -a
. /etc/letterman/pocketbase.env
set +a

exec sudo -u pocketbase --preserve-env=PB_FIELD_KEY /opt/letterman/pocketbase "$@" \
  --dir /opt/letterman/pb_data \
  --hooksDir /opt/letterman/pb_hooks \
  --migrationsDir /opt/letterman/pb_migrations \
  --encryptionEnv PB_FIELD_KEY
