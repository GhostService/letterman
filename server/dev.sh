#!/usr/bin/env bash
# Runs PocketBase on this Mac so the app in the Simulator has a server to talk to.
# Data lives in server/pb_data (not in git). Stop it with Ctrl+C.
#
#   ./dev.sh            start the server at http://127.0.0.1:8090 (dashboard: /_/)
#   python3 dev_seed.py fill it with demo accounts and data (run in a second terminal)
set -euo pipefail
cd "$(dirname "$0")"

# A local-only encryption key, made once. The real server has its own (see docs/SERVER_SETUP.md).
if [ ! -f .dev-key ]; then
  openssl rand -base64 24 | tr -d '\n' > .dev-key
fi
export PB_FIELD_KEY="$(cat .dev-key)"
# Every pocketbase command needs the same flags, including the key that encrypts its settings.
FLAGS=(--dir ./pb_data --hooksDir ./pb_hooks --migrationsDir ./pb_migrations --encryptionEnv PB_FIELD_KEY)

# Local dashboard admin (same login as in dev_seed.py). Creating it up front also stops
# PocketBase from opening a "create your first superuser" page in the browser.
./pocketbase superuser upsert admin@example.test devpassword123 "${FLAGS[@]}" > /dev/null

exec ./pocketbase serve --http 127.0.0.1:8090 "${FLAGS[@]}"
