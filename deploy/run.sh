#!/bin/bash
# Loads .env and execs one beltpack service.
#
# launchd has no notion of .env files, and putting secrets directly in a plist
# leaves them world-readable in ~/Library. This wrapper is the single place
# config gets loaded, for both `make run-*` and the LaunchAgents.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="${1:?usage: run.sh <livekit|token|bridge>}"

if [[ ! -f "$REPO/.env" ]]; then
  echo "run.sh: no $REPO/.env — copy .env.example and fill it in." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "$REPO/.env"
set +a

mkdir -p "$REPO/logs"

case "$SERVICE" in
  livekit)
    exec livekit-server --config "$REPO/deploy/livekit.yaml"
    ;;
  token)
    exec node "$REPO/token/server.mjs"
    ;;
  bridge)
    BIN="$REPO/server/.build/release/BeltpackBridge"
    if [[ ! -x "$BIN" ]]; then
      echo "run.sh: $BIN missing — run 'make server' first." >&2
      exit 1
    fi
    exec "$BIN"
    ;;
  *)
    echo "run.sh: unknown service '$SERVICE'" >&2
    exit 1
    ;;
esac
