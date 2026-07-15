#!/usr/bin/env bash
# Pull Production env vars from every live Vercel project into deploy/pulled-env/
# so you can review/edit locally. Files are gitignored — never commit secrets.
#
# Prerequisites:
#   npx vercel login
#
# Usage:
#   npm run env:pull
#   bash scripts/vercel-env-pull-all.sh home bolton   # subset only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VC="npx vercel"
OUT_DIR="$ROOT/deploy/pulled-env"
mkdir -p "$OUT_DIR"

if ! $VC whoami >/dev/null 2>&1; then
  echo ""
  echo "  Not logged in. Run:"
  echo "    npx vercel login"
  echo ""
  exit 1
fi

echo "  Vercel account: $($VC whoami)"
echo "  Writing to: deploy/pulled-env/"
echo ""

# app_name -> vercel_project_name
project_for() {
  case "$1" in
    home)   echo "11am-home" ;;
    bolton) echo "11am-fullsuite-bolton" ;;
    leo)    echo "11am-leo" ;;
    marc)   echo "11am-marc" ;;
    william) echo "11am-william" ;;
    george) echo "11am-george" ;;
    james)  echo "11am-james" ;;
    conner) echo "11am-conner" ;;
    robert) echo "11am-robert" ;;
    harris) echo "11am-harris" ;;
    cole)   echo "11am-cole" ;;
    johnny) echo "11am-johnny" ;;
    *)      echo "" ;;
  esac
}

ALL_APPS="home bolton leo marc william george james conner robert harris cole johnny"
APPS="${*:-$ALL_APPS}"

pull_one() {
  local app="$1"
  local project
  project=$(project_for "$app")
  local dir="$ROOT/apps/$app"
  local out="$OUT_DIR/$app.production.env"

  if [ -z "$project" ]; then
    echo "  ✗ unknown app: $app"
    return 1
  fi
  if [ ! -d "$dir" ]; then
    echo "  ✗ skip $app — no apps/$app"
    return 1
  fi

  echo "  ── $app ($project) ──"
  rm -f "$out"
  (cd "$dir" && $VC link --yes --project "$project" >/dev/null 2>&1 || true)
  if (cd "$dir" && $VC env pull "$out" --environment=production --yes >/dev/null 2>&1); then
    echo "  ✓ $out"
  else
    echo "  ✗ failed to pull $app — check project name in Vercel dashboard"
    return 1
  fi
}

for app in $APPS; do
  pull_one "$app" || true
done

# One combined file for easy side-by-side review
COMBINED="$OUT_DIR/ALL.production.env"
{
  echo "# 11am suite — pulled $(date '+%Y-%m-%d %H:%M')"
  echo "# DO NOT COMMIT — deploy/pulled-env/ is gitignored"
  echo ""
  for app in $APPS; do
    f="$OUT_DIR/$app.production.env"
    [ -f "$f" ] || continue
    echo "########## $app ##########"
    cat "$f"
    echo ""
  done
} > "$COMBINED"

echo ""
echo "  Done."
echo "  Per-app files: deploy/pulled-env/<app>.production.env"
echo "  Combined view: deploy/pulled-env/ALL.production.env"
echo ""
echo "  To list names only (no secret values):"
echo "    cd apps/home && npx vercel env ls production"
echo ""
