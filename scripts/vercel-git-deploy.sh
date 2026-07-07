#!/usr/bin/env bash
# Deploy via GitHub → Vercel (recommended). One repo, import projects in the browser.
#
# Usage:
#   npm run deploy:git          # home only (start here)
#   npm run deploy:git bolton   # show bolton steps too
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="${1:-home}"

echo ""
echo "  11am — Git → Vercel (no CLI deploy loop)"
echo "  ═══════════════════════════════════════════"
echo ""

# ── Git status ──
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "  ✗ Not a git repo. Run: git init && git add . && git commit -m 'Initial'"
  exit 1
fi

if git remote get-url origin >/dev/null 2>&1; then
  echo "  ✓ Remote: $(git remote get-url origin)"
else
  echo "  ✗ No git remote. Push to GitHub first:"
  echo "     gh repo create 11am --private --source=. --push"
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo ""
  echo "  ⚠  You have uncommitted changes. Commit and push before Vercel will see them:"
  echo "     git add -A && git commit -m 'Deploy config' && git push origin main"
  echo ""
else
  ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
  if [ "$ahead" != "0" ]; then
    echo "  ⚠  $ahead commit(s) not pushed yet. Run: git push origin main"
    echo ""
  else
    echo "  ✓ Working tree clean and pushed"
  fi
fi

print_app() {
  local app="$1"
  local project root
  case "$app" in
    home)   project="11am-suite";     root="apps/home" ;;
    bolton) project="11am-suite-bolton"; root="apps/bolton" ;;
    leo)    project="11am-suite-leo";    root="apps/leo" ;;
    marc)   project="11am-suite-marc";   root="apps/marc" ;;
    *)      project="11am-suite-$app";   root="apps/$app" ;;
  esac

  echo ""
  echo "  ── $app → $project ──"
  echo ""
  echo "  1. Open https://vercel.com/new"
  echo "  2. Import Git Repository → select 11am (github.com/1i4mturn/11am)"
  echo "  3. Configure:"
  echo "       Project Name:    $project"
  echo "       Root Directory:  $root   ← click Edit, type this path"
  echo "       Framework:       Next.js (auto)"
  echo ""
  echo "     If you see a monorepo checkbox after setting Root Directory, leave it ON"
  echo "     (wording varies: “Include source files outside the Root Directory”)."
  echo ""
  echo "     Build / Install can stay on defaults — apps/$app/vercel.json handles the monorepo build."
  echo ""

  if [ "$app" = "bolton" ] || [ "$app" = "leo" ] || [ "$app" = "marc" ] || [ "$app" = "william" ] || [ "$app" = "george" ]; then
    echo "  4. Environment Variables (Production):"
    echo "       DATABASE_URL = (Neon pooled URL from apps/bolton/.env.local)"
    echo ""
  fi

  if [ "$app" = "home" ]; then
    echo "  4. Environment Variables — optional for first deploy (dashboard loads without them)."
    echo "     Add later from deploy/home-vercel.env when you have agent URLs."
    echo "       NEXT_PUBLIC_HOME_URL = https://$project.vercel.app"
    echo ""
  elif [ "$app" != "bolton" ]; then
    echo "  4. Environment Variables:"
    echo "       BOLTON_API_URL = https://11am-suite-bolton.vercel.app"
    echo ""
  fi

  echo "  5. Click Deploy"
  echo "  6. Every git push to main auto-redeploys this project."
  echo ""
}

print_app "$APP"

if [ "$APP" = "home" ]; then
  echo "  ── Recommended order ──"
  echo "  1. home   (dashboard — start here, one project)"
  echo "  2. bolton (memory API — needs DATABASE_URL)"
  echo "  3. leo, marc, … only when you want them live"
  echo ""
  echo "  Skip npm run deploy:all — that was the painful CLI loop."
  echo "  You can delete the half-broken CLI projects in Vercel if you want a clean slate."
  echo ""
  echo "  Next: npm run deploy:git bolton"
fi

echo "  Repo: https://github.com/1i4mturn/11am"
echo ""
