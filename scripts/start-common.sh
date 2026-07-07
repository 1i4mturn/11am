#!/usr/bin/env bash
# Shared setup for start scripts (env files + optional database).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -d node_modules ]; then
  echo "  Installing dependencies (first time)..."
  npm install
fi

for app in home william marc bolton leo george james conner robert harris cole johnny; do
  if [ ! -f "apps/$app/.env.local" ]; then
    cp "apps/$app/.env.example" "apps/$app/.env.local"
    echo "  Created apps/$app/.env.local"
  fi
done

if [ "${SKIP_DB:-}" = "1" ]; then
  echo "  Skipping database (SKIP_DB=1)."
elif command -v docker >/dev/null 2>&1; then
  echo "  Starting database..."
  npm run db:up
  npm run db:migrate
else
  echo ""
  echo "  ⚠  Docker not found — skipping database."
  echo "     Memory/Gmail features need Postgres: npm run db:up && npm run db:migrate"
  echo ""
fi
