#!/usr/bin/env bash
# Deploy all 11am apps to Vercel via CLI (after one-time login).
#
# Prerequisites:
#   1. npx vercel login          (browser — do this once)
#   2. apps/bolton/.env.local    with DATABASE_URL (Neon pooled)
#   3. Run once: bash scripts/vercel-configure-projects.sh
#      (builds from repo root — no "include outside root" checkbox needed)
#
# Usage:
#   bash scripts/vercel-deploy-all.sh           # deploy all
#   bash scripts/vercel-deploy-all.sh bolton leo home   # deploy subset
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VC="npx vercel"

if ! $VC whoami >/dev/null 2>&1; then
  echo ""
  echo "  Not logged in to Vercel CLI."
  echo "  Run this first in your terminal (browser login):"
  echo ""
  echo "    cd ~/Projects/11am"
  echo "    npx vercel login"
  echo ""
  exit 1
fi

echo "  Vercel account: $($VC whoami)"
echo ""

if [ -f apps/bolton/.env.local ]; then
  set -a
  # shellcheck disable=SC1091
  source apps/bolton/.env.local
  set +a
fi

if [ -z "${DATABASE_URL:-}" ]; then
  echo "  WARNING: DATABASE_URL not set in apps/bolton/.env.local"
  echo ""
fi

ALL_APPS="bolton leo marc william george james conner robert harris cole johnny home"
APPS="${*:-$ALL_APPS}"

url_for() {
  local app="$1"
  local f="$ROOT/deploy/.vercel-url-$app"
  [ -f "$f" ] && cat "$f" || echo ""
}

save_url() {
  local app="$1" url="$2"
  mkdir -p "$ROOT/deploy"
  echo "${url%/}" > "$ROOT/deploy/.vercel-url-$app"
}

# home = main suite URL; agents = 11am-suite-<agent>
project_name() {
  local app="$1"
  if [ "$app" = "home" ]; then
    echo "11am-suite"
  else
    echo "11am-suite-$app"
  fi
}

deploy_app() {
  local app="$1"
  local dir="$ROOT/apps/$app"
  local project
  project=$(project_name "$app")
  local bolton_url
  bolton_url=$(url_for bolton)
  local prod_url="https://${project}.vercel.app"
  local failed=0

  if [ ! -d "$dir" ]; then
    echo "  ✗ skip $app — no apps/$app"
    return
  fi

  echo "  ── deploying $app → $project ──"

  if [ ! -d "$dir/.vercel" ]; then
    rm -rf "$dir/.vercel" 2>/dev/null || true
    (cd "$dir" && $VC link --yes --project "$project" 2>/dev/null || $VC link --yes 2>/dev/null || true)
  fi

  if [ -n "${DATABASE_URL:-}" ] && [[ "$app" =~ ^(bolton|leo|marc|william|george)$ ]]; then
    (cd "$dir" && printf '%s' "$DATABASE_URL" | $VC env add DATABASE_URL production --force 2>/dev/null || true)
  fi

  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    (cd "$dir" && printf '%s' "$ANTHROPIC_API_KEY" | $VC env add ANTHROPIC_API_KEY production --force 2>/dev/null || true)
  fi

  if [ -n "$bolton_url" ] && [ "$app" != "bolton" ] && [ "$app" != "home" ]; then
    (cd "$dir" && printf '%s' "$bolton_url" | $VC env add BOLTON_API_URL production --force 2>/dev/null || true)
  fi

  if [ "$app" = "johnny" ]; then
    (cd "$dir" && printf '%s' "false" | $VC env add JOHNNY_JOBS_ENABLED production --force 2>/dev/null || true)
  fi

  local out
  # Deploy from repo root (--project), not apps/$app path (partial upload).
  out=$($VC deploy --prod --yes --project "$project" 2>&1) || failed=1
  echo "$out"

  if echo "$out" | grep -qE 'Error:|exited with [1-9]|npm error'; then
    failed=1
  fi

  if [ "$failed" -eq 1 ]; then
    echo "  ✗ $app — build failed (see logs above or Vercel dashboard)"
    echo "    https://vercel.com/dashboard → $project"
    echo ""
    return 1
  fi

  save_url "$app" "$prod_url"
  echo "  ✓ $app → $prod_url"
  echo ""
}

ORDER="bolton leo marc william george james conner robert harris cole johnny home"
for app in $ORDER; do
  echo " $APPS " | grep -q " $app " || continue
  deploy_app "$app" || true
done

home_url=$(url_for home)
bolton_url=$(url_for bolton)

if [ -n "$home_url" ] && [ -n "$bolton_url" ]; then
  agent_url() {
    local a="$1" v
    v=$(url_for "$a")
    if [ -n "$v" ]; then echo "$v"; return; fi
    if [ "$a" = "home" ]; then echo "https://11am-suite.vercel.app"; else echo "https://11am-suite-$a.vercel.app"; fi
  }
  echo "  Generating home env file…"
  bash "$ROOT/scripts/generate-home-env.sh" --full \
    "$bolton_url" \
    "$(agent_url leo)" \
    "$(agent_url marc)" \
    "$(agent_url william)" \
    "$(agent_url george)" \
    "$(agent_url james)" \
    "$(agent_url conner)" \
    "$(agent_url robert)" \
    "$(agent_url harris)" \
    "$(agent_url cole)" \
    "$(agent_url johnny)" \
    "$home_url"

  echo ""
  echo "  Paste deploy/home-vercel.env into Vercel → 11am-suite → Environment Variables"
  echo "  Then: cd apps/home && npx vercel --prod --yes"
fi

echo ""
echo "  Deployed URLs (saved under deploy/.vercel-url-*):"
for app in $ORDER; do
  u=$(url_for "$app")
  [ -n "$u" ] && echo "    $app  $u"
done
echo ""
