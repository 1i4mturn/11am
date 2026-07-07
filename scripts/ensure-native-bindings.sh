#!/usr/bin/env bash
# Cursor/Electron often runs Node under Rosetta (x64) on Apple Silicon.
# npm only installs optional natives for the install host arch, so we add x64
# bindings on macOS to avoid lightningcss / @tailwindcss/oxide load failures.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ ! -d node_modules/lightningcss ]]; then
  exit 0
fi

oxide_version="$(node -p "require('./node_modules/@tailwindcss/oxide/package.json').version" 2>/dev/null || echo "4.3.2")"
lightning_version="$(node -p "require('./node_modules/lightningcss/package.json').version" 2>/dev/null || echo "1.32.0")"

npm install \
  "lightningcss-darwin-x64@${lightning_version}" \
  "@tailwindcss/oxide-darwin-x64@${oxide_version}" \
  --force --no-save >/dev/null 2>&1 || true
