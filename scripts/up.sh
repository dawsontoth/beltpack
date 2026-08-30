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
# Tell the app which .env to read rather than leaving it to guess. Its guesses
# only cover a checkout at ~/Code/beltpack, ~/beltpack or ~/Developer/beltpack;
# anywhere else and it silently comes up with no config, no control panel, and
# the reason tucked behind the menu bar icon. This script knows the answer, so
# it should not be a guess. Read once at launch, hence before `open`.
defaults write org.beltpack.BeltpackHost beltpack.envPath "$REPO/.env" 2>/dev/null || true

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
# Probed, not asserted. This line used to be printed unconditionally, so it
# said the control panel was up whether or not anything was listening — which
# is the one place a booth Mac most needs to be told the truth.
ADMIN_PORT="${BELTPACK_ADMIN_PORT:-7884}"
# curl's exit status, not the status code it prints: with no -f it exits 0 for
# any HTTP reply — 401 from the passcode gate included, which means listening
# and is not a fault — and non-zero only when nothing accepted the connection.
# Reading the printed code invites `000` from curl and `000` from a fallback to
# concatenate into something that matches neither.
if curl -s -o /dev/null -m 2 "http://127.0.0.1:$ADMIN_PORT/" 2>/dev/null; then
  echo "Control:  http://127.0.0.1:$ADMIN_PORT/"
elif pgrep -x BeltpackHost >/dev/null; then
  echo "Control:  not responding, but the host app is running — click the"
  echo "          Beltpack icon in the menu bar; it says why, and lets you pick"
  echo "          the .env by hand."
else
  # No icon to click: telling somebody to click one is how a diagnostic wastes
  # the minute it was meant to save.
  echo "Control:  not responding, and the host app is not running — there is no"
  echo "          menu bar icon until it is. Build and start it with 'make mac',"
  echo "          then check 'make mac-logs-past SINCE=10m' and logs/bridge.log."
fi
[[ -n "${BELTPACK_CLIENT_URL:-}" ]] && echo "Phones:   $BELTPACK_CLIENT_URL"
echo
echo "Logs: make logs      Stop: make down"
