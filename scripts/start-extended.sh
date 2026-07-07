#!/usr/bin/env bash
# Extended dev — core dashboard + OAuth connectors (william · george).
# 6 Next.js processes. Good default when setting up integrations.
set -euo pipefail
cd "$(dirname "$0")/.."

echo ""
echo "  11am — extended dev (core + william · george)"
echo "  ─────────────────────────────────────"

bash scripts/start-common.sh

echo "  Home     →  http://localhost:3010  (dashboard · connectors)"
echo "  Bolton   →  http://localhost:3002  (memory)"
echo "  Leo      →  http://localhost:3006  (calendar · ask)"
echo "  Marc     →  http://localhost:3001  (inbox · gmail oauth)"
echo "  William  →  http://localhost:3000  (voice corpus · gmail oauth)"
echo "  George   →  http://localhost:3004  (finance · xero oauth)"
echo ""
echo "  Lighter:  npm start          (core — 4 apps)"
echo "  Heavier:  npm run start:full (all 12 apps)"
echo ""
echo "  Press Ctrl+C to stop"
echo "  ─────────────────────────────────────"
echo ""

bash scripts/stop.sh
echo ""

npm run dev:extended
