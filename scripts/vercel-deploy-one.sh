#!/usr/bin/env bash
# Deploy a single app from monorepo root (full repo, no subdirectory upload).
#
# Usage:
#   bash scripts/vercel-deploy-one.sh bolton
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

app="${1:?usage: vercel-deploy-one.sh <app>}"
VC="npx vercel"

if [ "$app" = "home" ]; then
  project="11am-suite"
else
  project="11am-suite-$app"
fi

if [ -f apps/bolton/.env.local ]; then
  set -a
  # shellcheck disable=SC1091
  source apps/bolton/.env.local
  set +a
fi

dir="$ROOT/apps/$app"
if [ ! -d "$dir/.vercel" ]; then
  (cd "$dir" && $VC link --yes --project "$project" 2>/dev/null || true)
fi

if [ -n "${DATABASE_URL:-}" ] && [[ "$app" =~ ^(bolton|leo|marc|william|george)$ ]]; then
  (cd "$dir" && printf '%s' "$DATABASE_URL" | $VC env add DATABASE_URL production --force 2>/dev/null || true)
fi

if [ "$app" = "johnny" ]; then
  (cd "$dir" && printf '%s' "false" | $VC env add JOHNNY_JOBS_ENABLED production --force 2>/dev/null || true)
fi

echo "  deploying $app → $project (from repo root)…"
out=$($VC deploy --prod --yes --project "$project" 2>&1) || true
echo "$out"

if echo "$out" | grep -qE 'Error:|exited with [1-9]|npm error'; then
  echo ""
  echo "  ✗ failed — open https://vercel.com and check $project build logs"
  exit 1
fi

echo ""
echo "  ✓ https://${project}.vercel.app"
