#!/bin/bash
# Starts everything the booth Mac needs, in the right order.
#
# LiveKit and the token service run in the background; the host app carries the
# audio bridge and the management page and runs in the user session, because a
# bundled app has its own microphone permission where a daemon does not.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

if [[ ! -f .env ]]; then
  echo "No .env yet. Run: ./scripts/setup.sh --lan" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

mkdir -p logs

start() { # start <name> <pattern> <command...>
  local name="$1" pattern="$2"; shift 2
  if pgrep -f "$pattern" >/dev/null; then
    echo "  $name already running"
    return
  fi
  "$@" >"$REPO/logs/$name.log" 2>&1 &
  echo "  $name started"
}

echo "Starting beltpack:"
start livekit "livekit-server --config" ./deploy/run.sh livekit
start token   "token/server.mjs"       ./deploy/run.sh token

# Wait for signalling before anything tries to join it.
for _ in $(seq 1 40); do
  curl -fsS --max-time 1 "http://127.0.0.1:7880" >/dev/null 2>&1 && break
  sleep 0.25
done

HOST_APP="$REPO/mac/build/Build/Products/Debug/BeltpackHost.app"
if [[ -d "$HOST_APP" ]]; then
  if pgrep -f "BeltpackHost" >/dev/null; then
    echo "  host app already running"
  else
    open "$HOST_APP"
    echo "  host app started"
  fi
else
  echo "  host app not built yet — run: make mac"
fi

echo
echo "LiveKit:  $(curl -fsS --max-time 2 http://127.0.0.1:7880 2>/dev/null || echo 'not responding')"
echo "Token:    $(curl -fsS --max-time 2 "http://127.0.0.1:${TOKEN_PORT:-7883}/healthz" 2>/dev/null || echo 'not responding')"
echo "Control:  http://127.0.0.1:${BELTPACK_ADMIN_PORT:-7884}/"
[[ -n "${BELTPACK_CLIENT_URL:-}" ]] && echo "Phones:   $BELTPACK_CLIENT_URL"
echo
echo "Logs: make logs      Stop: make down"
