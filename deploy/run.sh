#!/bin/bash
# Loads .env and execs one beltpack service.
#
# launchd has no notion of .env files, and putting secrets directly in a plist
# leaves them world-readable in ~/Library. This wrapper is the single place
# config gets loaded, for both `make run-*` and the LaunchAgents.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="${1:?usage: run.sh <livekit|token|bridge|pair>}"

if [[ ! -f "$REPO/.env" ]]; then
  echo "run.sh: no $REPO/.env — copy .env.example and fill it in." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "$REPO/.env"
set +a

# launchd hands a process a minimal PATH with no Homebrew on it, so a service
# that runs perfectly from a terminal fails at boot with "livekit-server: not
# found" and nothing else to go on. An interactive shell hides this, which is
# why it survives every test that starts from one.
for dir in /opt/homebrew/bin /usr/local/bin; do
  if [[ -d "$dir" && ":$PATH:" != *":$dir:"* ]]; then
    PATH="$dir:$PATH"
  fi
done
export PATH

mkdir -p "$REPO/logs"

case "$SERVICE" in
  livekit)
    # Secrets and the LAN address are injected here rather than living in
    # deploy/livekit.yaml, which is committed to a public repo.
    export LIVEKIT_KEYS="${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}"
    if [[ -z "${BELTPACK_NODE_IP:-}" ]]; then
      echo "run.sh: set BELTPACK_NODE_IP in .env to the LAN address of this Mac on the comms VLAN." >&2
      exit 1
    fi
    export NODE_IP="$BELTPACK_NODE_IP"
    # livekit.yaml binds loopback; a LAN test needs to override that without
    # editing a committed file.
    exec livekit-server --config "$REPO/deploy/livekit.yaml" \
      --bind "${BELTPACK_BIND:-127.0.0.1}"
    ;;
  token)
    # A version-managed node (nvm, fnm, asdf) lives under the home directory
    # and is put on PATH by a shell profile launchd never reads. autostart.sh
    # records the resolved path so a booth Mac does not depend on which shell
    # started it — falling back to whatever PATH offers when it was not.
    exec "${BELTPACK_NODE_BIN:-node}" "$REPO/token/server.mjs"
    ;;
  bridge)
    BIN="$REPO/server/.build/release/BeltpackBridge"
    if [[ ! -x "$BIN" ]]; then
      echo "run.sh: $BIN missing — run 'make server' first." >&2
      exit 1
    fi
    exec "$BIN"
    ;;
  pair)
    BIN="$REPO/server/.build/release/BeltpackBridge"
    [[ -x "$BIN" ]] || BIN="$REPO/server/.build/debug/BeltpackBridge"
    if [[ ! -x "$BIN" ]]; then
      echo "run.sh: build the bridge first with 'make server'." >&2
      exit 1
    fi
    exec "$BIN" --pair "${@:2}"
    ;;
  *)
    echo "run.sh: unknown service '$SERVICE'" >&2
    exit 1
    ;;
esac
