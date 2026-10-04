#!/usr/bin/env bash
# Runs a one-off pocketbase command on the VPS with the same folders and encryption key as the
# running server. Use it with sudo, for example:
#
#   sudo /opt/hourtracker/pb.sh superuser upsert you@example.com 'a-long-password'
#
# (See FIRST_SETUP.md, step B8.)
set -euo pipefail

set -a
. /etc/hourtracker/pocketbase.env
set +a

exec sudo -u pocketbase --preserve-env=PB_FIELD_KEY /opt/hourtracker/pocketbase "$@" \
  --dir /opt/hourtracker/pb_data \
  --hooksDir /opt/hourtracker/pb_hooks \
  --migrationsDir /opt/hourtracker/pb_migrations \
  --encryptionEnv PB_FIELD_KEY
