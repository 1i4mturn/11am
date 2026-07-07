#!/usr/bin/env bash
# Generate home Vercel env block after you have deployment URLs.
# Usage:
#   bash scripts/generate-home-env.sh \
#     https://11am-bolton.vercel.app \
#     https://11am-leo.vercel.app \
#     https://11am-marc.vercel.app \
#     https://11am-home.vercel.app
#
# Or with all 11 agents:
#   bash scripts/generate-home-env.sh --full \
#     BOLTON_URL LEO_URL MARC_URL WILLIAM_URL GEORGE_URL \
#     JAMES_URL CONNER_URL ROBERT_URL HARRIS_URL COLE_URL JOHNNY_URL HOME_URL
set -euo pipefail

if [ "${1:-}" = "--full" ]; then
  shift
  BOLTON="${1:-}"; LEO="${2:-}"; MARC="${3:-}"; WILLIAM="${4:-}"; GEORGE="${5:-}"
  JAMES="${6:-}"; CONNER="${7:-}"; ROBERT="${8:-}"; HARRIS="${9:-}"; COLE="${10:-}"
  JOHNNY="${11:-}"; HOME="${12:-}"
else
  BOLTON="${1:-}"
  LEO="${2:-}"
  MARC="${3:-}"
  HOME="${4:-}"
  WILLIAM="${5:-https://YOUR-WILLIAM.vercel.app}"
  GEORGE="${6:-https://YOUR-GEORGE.vercel.app}"
  JAMES="${7:-https://YOUR-JAMES.vercel.app}"
  CONNER="${8:-https://YOUR-CONNER.vercel.app}"
  ROBERT="${9:-https://YOUR-ROBERT.vercel.app}"
  HARRIS="${10:-https://YOUR-HARRIS.vercel.app}"
  COLE="${11:-https://YOUR-COLE.vercel.app}"
  JOHNNY="${12:-https://YOUR-JOHNNY.vercel.app}"
fi

strip() { echo "$1" | sed 's:/*$::'; }
BOLTON=$(strip "$BOLTON"); LEO=$(strip "$LEO"); MARC=$(strip "$MARC")
WILLIAM=$(strip "$WILLIAM"); GEORGE=$(strip "$GEORGE"); HOME=$(strip "$HOME")
JAMES=$(strip "$JAMES"); CONNER=$(strip "$CONNER"); ROBERT=$(strip "$ROBERT")
HARRIS=$(strip "$HARRIS"); COLE=$(strip "$COLE"); JOHNNY=$(strip "$JOHNNY")

if [ -z "$BOLTON" ] || [ -z "$HOME" ]; then
  echo "Usage: bash scripts/generate-home-env.sh BOLTON_URL LEO_URL MARC_URL HOME_URL"
  exit 1
fi

OUT="$(cd "$(dirname "$0")/.." && pwd)/deploy/home-vercel.env"
mkdir -p "$(dirname "$OUT")"

cat > "$OUT" <<EOF
# Paste into Vercel → home project → Environment Variables
MARC_API_URL=$MARC
WILLIAM_API_URL=$WILLIAM
LEO_API_URL=$LEO
GEORGE_API_URL=$GEORGE
BOLTON_API_URL=$BOLTON
JAMES_API_URL=$JAMES
CONNER_API_URL=$CONNER
ROBERT_API_URL=$ROBERT
HARRIS_API_URL=$HARRIS
COLE_API_URL=$COLE
JOHNNY_API_URL=$JOHNNY
NEXT_PUBLIC_HOME_URL=$HOME

NEXT_PUBLIC_MARC_APP_URL=$MARC
NEXT_PUBLIC_WILLIAM_APP_URL=$WILLIAM
NEXT_PUBLIC_LEO_APP_URL=$LEO
NEXT_PUBLIC_GEORGE_APP_URL=$GEORGE
NEXT_PUBLIC_BOLTON_APP_URL=$BOLTON
NEXT_PUBLIC_JAMES_APP_URL=$JAMES
NEXT_PUBLIC_CONNER_APP_URL=$CONNER
NEXT_PUBLIC_ROBERT_APP_URL=$ROBERT
NEXT_PUBLIC_HARRIS_APP_URL=$HARRIS
NEXT_PUBLIC_COLE_APP_URL=$COLE
NEXT_PUBLIC_JOHNNY_APP_URL=$JOHNNY
EOF

echo "Wrote $OUT"
echo ""
cat "$OUT"
