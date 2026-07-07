#!/usr/bin/env bash
# First deploy walkthrough: Neon → Bolton → (more agents) → Home
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo ""
echo "  11am — first Vercel deploy"
echo "  ═══════════════════════════════════════"
echo ""

# ── 0. Prerequisites ──
if ! command -v node >/dev/null 2>&1; then
  echo "  ✗ Node.js required. Install from https://nodejs.org"
  exit 1
fi

if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "  ⚠  No git repo yet. Vercel works best with GitHub:"
  echo "     cd $ROOT"
  echo "     git init && git add . && git commit -m 'Initial 11am suite'"
  echo "     gh repo create 11am --private --source=. --push"
  echo ""
  echo "     (Or deploy via CLI without Git — see step 4.)"
  echo ""
else
  echo "  ✓ Git repo found"
  if git remote get-url origin >/dev/null 2>&1; then
    echo "  ✓ Remote: $(git remote get-url origin)"
  else
    echo "  ⚠  No git remote — push to GitHub before importing to Vercel"
  fi
fi

echo ""
echo "  STEP 1 · Neon database (5 min)"
echo "  ───────────────────────────────────────"
echo "  1. Open https://console.neon.tech → Sign up (free)"
echo "  2. New Project → name: 11am"
echo "  3. Dashboard → Connect → copy POOLED connection string"
echo "  4. Run in terminal:"
echo ""
echo "     DATABASE_URL='postgresql://USER:PASS@HOST/neondb?sslmode=require' \\"
echo "       bash scripts/neon-migrate.sh"
echo ""
read -r -p "  Press Enter when Neon migrate finished (or skip for now)…" _

echo ""
echo "  STEP 2 · Deploy Bolton first"
echo "  ───────────────────────────────────────"
echo "  Option A — Vercel website (recommended first time):"
echo "  1. https://vercel.com/new → Import Git Repository"
echo "  2. Select your 11am repo"
echo "  3. Configure:"
echo "       Project name:  11am-bolton  (or similar)"
echo "       Root Directory: apps/bolton   ← important"
echo "       Framework:     Next.js (auto)"
echo "  4. Environment Variables → Add:"
echo "       DATABASE_URL     = (your Neon pooled URL)"
echo "       ANTHROPIC_API_KEY = (optional for now)"
echo "  5. Deploy"
echo "  6. Copy the URL, e.g. https://11am-bolton.vercel.app"
echo ""
echo "  Option B — Vercel CLI:"
if ! command -v vercel >/dev/null 2>&1; then
  echo "     npm i -g vercel"
fi
echo "     cd apps/bolton"
echo "     vercel login"
echo "     vercel link"
echo "     vercel env add DATABASE_URL production"
echo "     vercel --prod"
echo ""
read -r -p "  Paste your Bolton URL (or Enter to skip): " BOLTON_URL
BOLTON_URL="${BOLTON_URL%/}"

if [ -n "$BOLTON_URL" ]; then
  echo ""
  echo "  Testing Bolton…"
  if curl -sf "${BOLTON_URL}/api/memory?status=active" >/dev/null 2>&1; then
    echo "  ✓ ${BOLTON_URL}/api/memory responds"
  else
    echo "  ⚠  Bolton not responding yet — check Vercel deploy logs"
  fi
fi

echo ""
echo "  STEP 3 · Deploy Leo + Marc (same flow)"
echo "  ───────────────────────────────────────"
echo "  Repeat Step 2 for apps/leo and apps/marc"
echo "  Each needs: DATABASE_URL, BOLTON_API_URL=$BOLTON_URL"
echo "  Leo also: GOOGLE_* for calendar (can add later)"
echo "  Marc also: GOOGLE_* for gmail (can add later)"
echo ""
read -r -p "  Paste Leo URL (or Enter to skip): " LEO_URL
read -r -p "  Paste Marc URL (or Enter to skip): " MARC_URL
LEO_URL="${LEO_URL%/}"; MARC_URL="${MARC_URL%/}"

echo ""
echo "  STEP 4 · Deploy Home last"
echo "  ───────────────────────────────────────"
echo "  Root Directory: apps/home"
echo "  Project name: 11am-home"
echo ""

if [ -n "$BOLTON_URL" ]; then
  HOME_PLACEHOLDER="https://YOUR-HOME.vercel.app"
  bash scripts/generate-home-env.sh \
    "${BOLTON_URL:-https://YOUR-BOLTON.vercel.app}" \
    "${LEO_URL:-https://YOUR-LEO.vercel.app}" \
    "${MARC_URL:-https://YOUR-MARC.vercel.app}" \
    "$HOME_PLACEHOLDER"
  echo ""
  echo "  ↑ Copy deploy/home-vercel.env into Vercel → home → Environment Variables"
  echo "  Then update NEXT_PUBLIC_HOME_URL after home deploys."
else
  echo "  After deploy, run:"
  echo "    bash scripts/generate-home-env.sh BOLTON_URL LEO_URL MARC_URL HOME_URL"
fi

echo ""
echo "  STEP 5 · Verify"
echo "  ───────────────────────────────────────"
echo "  Open home URL → dashboard should show Bolton memory in WIP/Activity"
echo "  Sidebar agent links work once you deploy more apps + update env"
echo ""
echo "  Next agents: npm run deploy:vercel  (full checklist)"
echo ""
