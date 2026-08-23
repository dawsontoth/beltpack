#!/bin/bash
# Stops everything scripts/up.sh started. Leaves logs in place.
set -uo pipefail

stop() { # stop <name> <pattern>
  if pgrep -f "$2" >/dev/null; then
    pkill -f "$2" && echo "  $1 stopped"
  else
    echo "  $1 not running"
  fi
}

echo "Stopping beltpack:"
stop "host app" "BeltpackHost"
stop "bridge"   "BeltpackBridge"
stop "token"    "token/server.mjs"
stop "livekit"  "livekit-server --config"
