#!/usr/bin/env bash
# Run Bolton schema migrations against Neon (or any remote Postgres).
# Usage: DATABASE_URL='postgresql://...' bash scripts/neon-migrate.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: Set DATABASE_URL to your Neon connection string."
  echo ""
  echo "  1. Open https://console.neon.tech → your project → Connect"
  echo "  2. Copy the connection string (use \"Pooled connection\" for Vercel)"
  echo "  3. Run with your REAL string — not USER/PASS/HOST placeholders:"
  echo ""
  echo "     DATABASE_URL='postgresql://neondb_owner:xxxx@ep-xxxx.ap-southeast-2.aws.neon.tech/neondb?sslmode=require' bash scripts/neon-migrate.sh"
  exit 1
fi

if [[ "$DATABASE_URL" == *"@HOST"* ]] || [[ "$DATABASE_URL" == *"USER:PASS"* ]] || [[ "$DATABASE_URL" == *"://USER:"* ]]; then
  echo "ERROR: DATABASE_URL still has placeholder text (USER, PASS, or HOST)."
  echo ""
  echo "  Replace it with the actual string from Neon console → Connect."
  echo "  It should look like:"
  echo "  postgresql://neondb_owner:AbCdEf123@ep-cool-name-12345678.ap-southeast-2.aws.neon.tech/neondb?sslmode=require"
  exit 1
fi

echo "Migrating shared 11am schema to remote Postgres…"
npm run db:migrate -w @11am/bolton
echo "Done."
