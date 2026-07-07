#!/usr/bin/env bash
# Start Postgres only (requires Docker Desktop).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v docker >/dev/null 2>&1; then
  echo ""
  echo "  Docker is not installed or not in your PATH."
  echo ""
  echo "  Install Docker Desktop for Mac:"
  echo "  https://docs.docker.com/desktop/setup/install/mac-install/"
  echo ""
  echo "  After installing, open Docker Desktop, wait until it says"
  echo "  'Docker is running', then run:"
  echo ""
  echo "    npm run db:up"
  echo "    npm run db:migrate"
  echo ""
  exit 1
fi

npm run db:up
npm run db:migrate
echo ""
echo "  Database ready at postgresql://elevenam:elevenam@localhost:5435/elevenam"
