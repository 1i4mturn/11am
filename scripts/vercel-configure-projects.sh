#!/usr/bin/env bash
# One-time: point each Vercel project at the monorepo ROOT (no "include outside root" needed).
#
# In dashboard, clear Root Directory if it was set (Settings → Build and Deployment → Root Directory → empty → Save).
#
# Usage:
#   bash scripts/vercel-configure-projects.sh
#   bash scripts/vercel-configure-projects.sh bolton home
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VC="npx vercel"

if ! $VC whoami >/dev/null 2>&1; then
  echo "Run: npx vercel login"
  exit 1
fi

ALL_APPS="bolton leo marc william george james conner robert harris cole johnny home"
APPS="${*:-$ALL_APPS}"

project_name() {
  local app="$1"
  if [ "$app" = "home" ]; then
    echo "11am-suite"
  else
    echo "11am-suite-$app"
  fi
}

for app in $APPS; do
  project=$(project_name "$app")
  echo "  configuring $project (build @11am/$app from repo root)…"
  $VC project update "$project" \
    --framework nextjs \
    --build-command "npm run build -w @11am/$app" \
    --output-directory "apps/$app/.next" \
    --install-command "npm install"
done

echo ""
echo "  Done. Deploy one app to test:"
echo "    npm run deploy:one bolton"
echo ""
