#!/usr/bin/env bash
# Run the complete test suite against a fresh Linux instance.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v cjpm >/dev/null 2>&1; then
  echo "cjpm not found. Load the Cangjie environment first." >&2
  exit 1
fi

PORT="${CANGMO_TEST_PORT:-18090}"
DATA_DIR="${CANGMO_TEST_DATA:-./data/test-linux}"
export CANGMO_SETUP_TOKEN="${CANGMO_SETUP_TOKEN:-test-setup-token-123456}"
export CANGMO_BASE="http://127.0.0.1:${PORT}"
export CANGMO_BACKUP_PASSPHRASE="${CANGMO_BACKUP_PASSPHRASE:-test-backup-passphrase-2026}"

rm -rf "${DATA_DIR}"
mkdir -p "${DATA_DIR}"
cjpm build

./target/release/bin/main serve --config "${DATA_DIR}/config.json" --port "${PORT}" &
SERVER_PID=$!
trap 'kill "${SERVER_PID}" 2>/dev/null || true' EXIT
sleep 2

cjpm test
node tests/smoke.mjs
node tests/e2e.mjs
node tests/extended.mjs
node tests/v101.mjs
node tests/v110.mjs
node tests/v120.mjs
node tests/v121-token.mjs
node tests/v121-search.mjs
node tests/v121-crypto.mjs
node tests/load.mjs
node tests/security.mjs
node tests/v130.mjs
