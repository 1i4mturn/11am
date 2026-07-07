#!/usr/bin/env bash
# Stop 11am dev servers on suite ports 3000–3011.
set -euo pipefail

stopped=0
for port in 3000 3001 3002 3003 3004 3005 3006 3007 3008 3009 3010 3011; do
  pids=$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "  Stopping process on port $port..."
    kill $pids 2>/dev/null || true
    stopped=1
  fi
done

if [ "$stopped" -eq 1 ]; then
  sleep 1
  echo "  Done."
else
  echo "  No dev servers running on ports 3000–3011."
fi
