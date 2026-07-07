#!/usr/bin/env bash
# Full suite — all 12 apps. Heavy on CPU/RAM; use start.sh (core) for day-to-day work.
set -euo pipefail
cd "$(dirname "$0")/.."

echo ""
echo "  11am — full dev (all 12 apps)"
echo "  ─────────────────────────────────────"

bash scripts/start-common.sh

echo "  Home     →  http://localhost:3010"
echo "  William  →  http://localhost:3000"
echo "  Marc     →  http://localhost:3001"
echo "  Bolton   →  http://localhost:3002"
echo "  James    →  http://localhost:3003"
echo "  George   →  http://localhost:3004"
echo "  Conner   →  http://localhost:3005"
echo "  Leo      →  http://localhost:3006"
echo "  Robert   →  http://localhost:3007"
echo "  Harris   →  http://localhost:3008"
echo "  Cole     →  http://localhost:3009"
echo "  Johnny   →  http://localhost:3011"
echo ""
echo "  Lighter:  npm start              (core — 4 apps)"
echo "  Middle:   npm run start:extended (6 apps · oauth)"
echo ""
echo "  Press Ctrl+C to stop all servers"
echo "  ─────────────────────────────────────"
echo ""

bash scripts/stop.sh
echo ""

npm run dev:full
