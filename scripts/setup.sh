#!/bin/bash
# Beltpack setup.
#
# Idempotent by design: run it as many times as you like. Every step reports
# whether it did something or found it already done, and an existing secret is
# never silently replaced.
#
#   ./scripts/setup.sh --dev          this laptop, no WING, loopback only
#   ./scripts/setup.sh --lan          same, but reachable by phones on the LAN
#   ./scripts/setup.sh --production   the booth Mac wired to the console
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO/.env"
EXAMPLE_FILE="$REPO/.env.example"

MODE=""
ASSUME_YES=false
DO_INSTALL=false

# ---- output ---------------------------------------------------------------

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
  RED=$'\033[31m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; GREEN=""; YELLOW=""; RED=""; CYAN=""; RESET=""
fi

step()  { printf '\n%s==>%s %s%s%s\n' "$CYAN" "$RESET" "$BOLD" "$1" "$RESET"; }
did()   { printf '    %s+%s %s\n' "$GREEN" "$RESET" "$1"; }
skip()  { printf '    %s.%s %s%s%s\n' "$DIM" "$RESET" "$DIM" "$1" "$RESET"; }
warn()  { printf '    %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }
fail()  { printf '\n%serror:%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }

TODO=()
todo() { TODO+=("$1"); }

usage() {
  sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---- args -----------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev) MODE=dev ;;
    --lan) MODE=lan ;;
    --production|--prod) MODE=production ;;
    --install) DO_INSTALL=true ;;
    --yes|-y) ASSUME_YES=true ;;
    --help|-h) usage ;;
    *) fail "unknown option '$1' (try --help)" ;;
  esac
  shift
done

confirm() {
  $ASSUME_YES && return 0
  [[ -t 0 ]] || return 1
  read -r -p "    ${1} [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ---- .env helpers ---------------------------------------------------------

env_get() {
  [[ -f "$ENV_FILE" ]] || return 0
  awk -v k="$1" '
    index($0, k "=") == 1 {
      sub(/^[^=]*=/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$ENV_FILE"
}

# Update in place if the key exists, append otherwise. Order and comments in
# the file are preserved either way.
env_set() {
  local key="$1" value="$2"
  if [[ -f "$ENV_FILE" ]] && grep -q "^${key}=" "$ENV_FILE"; then
    awk -v k="$key" -v v="$value" '
      index($0, k "=") == 1 { print k "=\"" v "\""; next }
      { print }
    ' "$ENV_FILE" > "$ENV_FILE.tmp"
    mv "$ENV_FILE.tmp" "$ENV_FILE"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$ENV_FILE"
  fi
  chmod 600 "$ENV_FILE"
}

# A value counts as unset if it is empty or still one of the shipped
# placeholders. Anything else is treated as real and left alone.
is_placeholder() {
  local value="$1"
  [[ -z "$value" ]] && return 0
  case "$value" in
    CHANGE-ME*|REPLACE-*|change-me|changeme|GET\ FROM*|192.168.10.10|comms.example.org) return 0 ;;
  esac
  return 1
}

# ---- 0. mode --------------------------------------------------------------

if [[ -z "$MODE" ]]; then
  if [[ -f "$ENV_FILE" ]] && [[ "$(env_get BELTPACK_NODE_IP)" == "127.0.0.1" ]]; then
    MODE=dev
  else
    fail "pick a mode: --dev (this laptop) or --production (the booth Mac)"
  fi
fi

printf '%sbeltpack setup%s  %s(%s)%s\n' "$BOLD" "$RESET" "$DIM" "$MODE" "$RESET"

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS only — the bridge uses Core Audio."

# ---- 1. dependencies ------------------------------------------------------

step "Dependencies"

command -v brew >/dev/null || fail "Homebrew not found. Install it from https://brew.sh first."

MISSING=()
need() {
  if command -v "$1" >/dev/null; then
    skip "$1 already installed"
  else
    MISSING+=("$2")
    warn "$1 missing (brew formula: $2)"
  fi
}

need livekit-server livekit
need lk livekit-cli
need node node

if [[ ${#MISSING[@]} -gt 0 ]]; then
  if $DO_INSTALL || confirm "Install ${MISSING[*]} with Homebrew?"; then
    brew install "${MISSING[@]}"
    did "installed ${MISSING[*]}"
  else
    todo "Install missing tools: brew install ${MISSING[*]}"
    warn "skipping install — rerun with --install to do it automatically"
  fi
fi

# ---- 2. .env --------------------------------------------------------------

step "Configuration file"

if [[ -f "$ENV_FILE" ]]; then
  skip ".env exists — existing values will be kept"
else
  cp "$EXAMPLE_FILE" "$ENV_FILE"
  did "created .env from .env.example"
fi
chmod 600 "$ENV_FILE"

# ---- 3. API credentials ---------------------------------------------------

step "LiveKit credentials"

CURRENT_KEY="$(env_get LIVEKIT_API_KEY)"
CURRENT_SECRET="$(env_get LIVEKIT_API_SECRET)"

if is_placeholder "$CURRENT_KEY" || is_placeholder "$CURRENT_SECRET" || [[ ${#CURRENT_SECRET} -lt 32 ]]; then
  if command -v livekit-server >/dev/null; then
    # Output is "API Key:  <key>" / "API Secret:  <secret>" — note Go's
    # Println puts two spaces after the colon.
    GENERATED="$(livekit-server generate-keys 2>/dev/null)"
    NEW_KEY="$(printf '%s\n' "$GENERATED" | awk -F'API Key:[[:space:]]*' '/API Key:/{print $2; exit}')"
    NEW_SECRET="$(printf '%s\n' "$GENERATED" | awk -F'API Secret:[[:space:]]*' '/API Secret:/{print $2; exit}')"

    if [[ -n "$NEW_KEY" && -n "$NEW_SECRET" && ${#NEW_SECRET} -ge 32 ]]; then
      env_set LIVEKIT_API_KEY "$NEW_KEY"
      env_set LIVEKIT_API_SECRET "$NEW_SECRET"
      did "generated a new API key and secret"
    else
      fail "could not parse 'livekit-server generate-keys' output"
    fi
  else
    todo "Generate credentials: livekit-server generate-keys, then rerun this script"
    warn "livekit-server not installed yet — skipping credential generation"
  fi
else
  skip "credentials already set (key ${CURRENT_KEY:0:8}…)"
fi

# ---- 4. passcode ----------------------------------------------------------

step "Join passcode"

if is_placeholder "$(env_get BELTPACK_PASSCODE)"; then
  # Unambiguous alphabet: no 0/O/1/l/I, because volunteers type this by hand.
  # Subshell with pipefail off: tr takes SIGPIPE when head closes the pipe,
  # which would otherwise trip set -e and kill the script here.
  PASSCODE="$(set +o pipefail; LC_ALL=C tr -dc 'abcdefghijkmnpqrstuvwxyz23456789' < /dev/urandom | head -c 10)"
  env_set BELTPACK_PASSCODE "$PASSCODE"
  did "generated passcode: ${BOLD}${PASSCODE}${RESET}"
  warn "write that down — it is what volunteers type once on each phone"
else
  skip "passcode already set"
fi

# ---- 4b. admin passcode ---------------------------------------------------

step "Management passcode"

if is_placeholder "$(env_get BELTPACK_ADMIN_PASSCODE)"; then
  ADMIN="$(set +o pipefail; LC_ALL=C tr -dc 'abcdefghijkmnpqrstuvwxyz23456789' < /dev/urandom | head -c 14)"
  env_set BELTPACK_ADMIN_PASSCODE "$ADMIN"
  did "generated management passcode: ${BOLD}${ADMIN}${RESET}"
  warn "this one is not on the QR codes — it can re-patch the console"
else
  skip "management passcode already set"
fi

# ---- 5. network address ---------------------------------------------------

step "Network address"

CURRENT_IP="$(env_get BELTPACK_NODE_IP)"

detect_lan_ip() {
  # Prefer the default-route interface; it is the one a phone will reach.
  local iface
  iface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
  [[ -n "$iface" ]] && ipconfig getifaddr "$iface" 2>/dev/null && return 0
  for i in $(networksetup -listallhardwareports 2>/dev/null | awk '/Device:/{print $2}'); do
    local a; a="$(ipconfig getifaddr "$i" 2>/dev/null || true)"
    [[ -n "$a" ]] && { printf '%s' "$a"; return 0; }
  done
  return 1
}

if [[ "$MODE" == "dev" ]]; then
  if [[ "$CURRENT_IP" != "127.0.0.1" ]]; then
    env_set BELTPACK_NODE_IP "127.0.0.1"
    did "set node IP to 127.0.0.1 (loopback — same-machine testing only)"
  else
    skip "node IP already 127.0.0.1"
  fi
  env_set BELTPACK_PUBLIC_URL "ws://127.0.0.1:7880"
  env_set BELTPACK_CLIENT_URL "http://127.0.0.1:$(env_get TOKEN_PORT)"
  env_set BELTPACK_BIND "127.0.0.1"
  env_set TOKEN_BIND "127.0.0.1"
elif [[ "$MODE" == "lan" ]]; then
  # No TLS here. Fine for a bench test on a trusted network, not for a
  # service — production puts Caddy in front and goes back to loopback.
  if LAN_IP="$(detect_lan_ip)"; then
    env_set BELTPACK_NODE_IP "$LAN_IP"
    env_set BELTPACK_PUBLIC_URL "ws://${LAN_IP}:7880"
    env_set BELTPACK_CLIENT_URL "http://${LAN_IP}:$(env_get TOKEN_PORT)"
    env_set BELTPACK_BIND "0.0.0.0"
    env_set TOKEN_BIND "0.0.0.0"
    did "listening on all interfaces, advertising $LAN_IP"
    warn "cleartext on the LAN — bench testing only, no TLS"
    printf '      %sPoint the phone at:%s %shttp://%s:7883%s\n' "$DIM" "$RESET" "$BOLD" "$LAN_IP" "$RESET"
  else
    todo "Could not detect a LAN address; set BELTPACK_NODE_IP by hand"
  fi
else
  if is_placeholder "$CURRENT_IP"; then
    DETECTED=""
    for iface in $(networksetup -listallhardwareports 2>/dev/null | awk '/Device:/{print $2}'); do
      addr="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
      [[ -n "$addr" ]] && { DETECTED="$addr"; break; }
    done

    if [[ -n "$DETECTED" ]]; then
      env_set BELTPACK_NODE_IP "$DETECTED"
      did "detected LAN address $DETECTED"
      warn "confirm this is the comms VLAN address, not a different network"
    else
      todo "Set BELTPACK_NODE_IP in .env to this Mac's address on the comms VLAN"
      warn "could not detect a LAN address"
    fi
  else
    skip "node IP already set ($CURRENT_IP)"
  fi
fi

# ---- 6. audio input -------------------------------------------------------

step "Console input"

DEVICE_OUTPUT=""
if [[ -x "$REPO/server/.build/release/BeltpackBridge" ]]; then
  DEVICE_OUTPUT="$("$REPO/server/.build/release/BeltpackBridge" --devices 2>/dev/null || true)"
elif [[ -x "$REPO/server/.build/debug/BeltpackBridge" ]]; then
  DEVICE_OUTPUT="$("$REPO/server/.build/debug/BeltpackBridge" --devices 2>/dev/null || true)"
fi

if [[ -z "$DEVICE_OUTPUT" ]]; then
  todo "Build the bridge (make server), then rerun to pick an input device"
  warn "bridge not built yet — cannot enumerate audio devices"
elif printf '%s' "$DEVICE_OUTPUT" | grep -q "grant Microphone permission"; then
  warn "macOS is withholding device names until Microphone access is granted"
  printf '      %sRun this in Terminal.app and approve the prompt:%s\n' "$DIM" "$RESET"
  printf '      %smake devices%s\n' "$BOLD" "$RESET"
  todo "Grant Microphone permission, then rerun this script"
else
  printf '%s\n' "$DEVICE_OUTPUT" | sed 's/^/      /'
  CURRENT_DEVICE="$(env_get BELTPACK_INPUT_DEVICE)"
  if printf '%s' "$DEVICE_OUTPUT" | grep -qi -- "$CURRENT_DEVICE"; then
    skip "BELTPACK_INPUT_DEVICE=\"$CURRENT_DEVICE\" matches a device above"
  else
    warn "BELTPACK_INPUT_DEVICE=\"$CURRENT_DEVICE\" matches nothing above"
    todo "Set BELTPACK_INPUT_DEVICE in .env to one of the devices listed above"
  fi
fi

# ---- 7. smoke test --------------------------------------------------------

step "Smoke test"

if command -v livekit-server >/dev/null && [[ ${#TODO[@]} -eq 0 || -n "$(env_get LIVEKIT_API_SECRET)" ]]; then
  set -a; source "$ENV_FILE"; set +a
  export LIVEKIT_KEYS="${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}"
  export NODE_IP="${BELTPACK_NODE_IP}"

  livekit-server --config "$REPO/deploy/livekit.yaml" >/tmp/beltpack-smoke.log 2>&1 &
  SMOKE_PID=$!
  trap 'kill $SMOKE_PID 2>/dev/null || true' EXIT

  HEALTHY=false
  for _ in $(seq 1 20); do
    if curl -fsS --max-time 1 http://127.0.0.1:7880 >/dev/null 2>&1; then HEALTHY=true; break; fi
    sleep 0.5
  done

  if $HEALTHY; then
    did "LiveKit started and answered its health check on :7880"
  else
    warn "LiveKit did not come up — see /tmp/beltpack-smoke.log"
    todo "Investigate LiveKit startup: tail /tmp/beltpack-smoke.log"
  fi

  kill $SMOKE_PID 2>/dev/null || true
  wait $SMOKE_PID 2>/dev/null || true
  trap - EXIT
else
  skip "skipped — install livekit-server and rerun"
fi

# ---- done -----------------------------------------------------------------

printf '\n%s%s%s\n' "$BOLD" "────────────────────────────────────────" "$RESET"

if [[ ${#TODO[@]} -eq 0 ]]; then
  printf '%sReady.%s Start it with three terminals:\n\n' "$GREEN" "$RESET"
  printf '    make run-livekit\n    make run-token\n    make run-bridge\n'
  if [[ "$MODE" == "dev" ]]; then
    printf '\n%sDev mode is loopback only%s — phones on the network cannot reach this.\n' "$DIM" "$RESET"
    printf '%sTest from a browser on this Mac at http://localhost:8080 (make -C web serve).%s\n' "$DIM" "$RESET"
  fi
else
  printf '%sAlmost — %d thing(s) left:%s\n\n' "$YELLOW" "${#TODO[@]}" "$RESET"
  for item in "${TODO[@]}"; do printf '    • %s\n' "$item"; done
  printf '\n%sRerun this script afterwards; it will skip what is already done.%s\n' "$DIM" "$RESET"
fi
