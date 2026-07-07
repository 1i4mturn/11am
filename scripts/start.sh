#!/usr/bin/env bash
# Lighter local dev — home + the 3 backends the dashboard actually calls.
# ~4 Next.js processes instead of 12. Use start-full.sh when you need every agent.
set -euo pipefail
cd "$(dirname "$0")/.."

echo ""
echo "  11am — core dev (home · bolton · leo · marc)"
echo "  ─────────────────────────────────────"

bash scripts/start-common.sh

echo "  Home     →  http://localhost:3010  (dashboard)"
echo "  Bolton   →  http://localhost:3002  (memory)"
echo "  Leo      →  http://localhost:3006  (calendar · ask)"
echo "  Marc     →  http://localhost:3001  (inbox)"
echo ""
echo "  Need another agent?  npm run dev -w @11am/johnny"
echo "  OAuth / connectors: npm run start:extended"
echo "  Full suite (12 apps): npm run start:full"
echo ""
echo "  Press Ctrl+C to stop"
echo "  ─────────────────────────────────────"
echo ""

bash scripts/stop.sh
echo ""

npm run dev:core
