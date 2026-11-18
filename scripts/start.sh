#!/usr/bin/env bash
# Build and start Cangmo on Linux.
# Prerequisites: Cangjie 1.2.1 toolchain, libssl-dev (Debian/Ubuntu) or
# openssl-devel (Fedora/RHEL), and the Cangjie runtime libraries in PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v cjpm >/dev/null 2>&1; then
  echo "cjpm not found. Load the Cangjie environment first: source /path/to/cangjie/envsetup.sh" >&2
  exit 1
fi

cjpm build
exec ./target/release/bin/main serve "$@"
