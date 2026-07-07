#!/usr/bin/env bash
# 11am suite doctor — one command to confirm everything is wired and running.
# Usage: npm run doctor        (checks env + code health)
#        npm run doctor -- --live   (also pings every running app)
set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0; WARN=0; FAIL=0
ok()   { echo "  ok    $1"; PASS=$((PASS+1)); }
warn() { echo "  warn  $1"; WARN=$((WARN+1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

echo "11am doctor — $(date '+%Y-%m-%d %H:%M')"
echo
echo "environment"
node -v >/dev/null 2>&1 && ok "node $(node -v)" || bad "node not found"
[ -d node_modules ] && ok "node_modules installed" || bad "run npm install"

APPS="home william marc bolton james george conner robert harris cole leo johnny"
for app in $APPS; do
  if [ -f "apps/$app/.env.local" ]; then
    if grep -q "ANTHROPIC_API_KEY=..*" "apps/$app/.env.local" 2>/dev/null; then
      ok "$app .env.local (anthropic key set)"
    else
      warn "$app .env.local exists but ANTHROPIC_API_KEY looks unset"
    fi
  else
    warn "$app missing .env.local (npm run setup copies the example)"
  fi
done

echo
echo "code health"
if npm test >/tmp/11am-doctor-test.log 2>&1; then
  ok "unit tests pass"
else
  bad "unit tests failing — see /tmp/11am-doctor-test.log"
fi

echo
if [ "${1:-}" = "--live" ]; then
  echo "live apps"
  ports="home:3010 william:3000 marc:3001 bolton:3002 james:3003 george:3004 conner:3005 leo:3006 robert:3007 harris:3008 cole:3009 johnny:3011"
  for pair in $ports; do
    name="${pair%%:*}"; port="${pair##*:}"
    code=$(curl -s -o /dev/null -m 4 -w "%{http_code}" "http://localhost:$port/" 2>/dev/null || echo "000")
    case "$code" in
      2*|3*) ok "$name responding on :$port" ;;
      000)   warn "$name not running on :$port" ;;
      *)     bad "$name on :$port returned HTTP $code" ;;
    esac
  done
  echo
fi

echo "summary: $PASS ok, $WARN warnings, $FAIL failures"
[ "$FAIL" -eq 0 ] || exit 1
