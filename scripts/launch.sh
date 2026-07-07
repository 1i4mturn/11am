#!/usr/bin/env bash
# 11am — full suite launcher
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# GUI/double-click launches often have a minimal PATH — ensure node/npm resolve
export PATH="/usr/local/bin:/opt/homebrew/bin:${HOME}/.local/bin:/usr/bin:/bin:${PATH:-}"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm not found. Install Node.js or add it to PATH, then retry."
  exit 1
fi

# Install deps if needed
if [ ! -d "$ROOT/node_modules" ]; then
  cd "$ROOT" && npm install --silent
fi

# Kill anything already on our ports
for PORT in 3000 3001 3002 3006 3010; do
  lsof -ti tcp:$PORT | xargs kill -9 2>/dev/null || true
done

# Start all apps in background, log to /tmp
start_app() {
  local name="$1"
  local script="$2"
  local log="/tmp/11am-${name}.log"
  : > "$log"
  nohup env PATH="$PATH" npm run "$script" </dev/null >>"$log" 2>&1 &
  disown $! 2>/dev/null || true
}

cd "$ROOT"
start_app home dev:home
start_app william dev:william
start_app marc dev:marc
start_app bolton dev:bolton

# Wait for the home server to be ready (max 30s)
echo "Waiting for 11am to start..."
for i in $(seq 1 30); do
  if curl -s http://localhost:3010 > /dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Open in Chrome
open -a "Google Chrome" http://localhost:3010
