#!/usr/bin/env bash
#
# Start beltpack when the booth Mac comes up.
#
# LaunchAgents rather than LaunchDaemons, and that choice decides everything
# else here: capturing the console counts as microphone access under macOS, and
# TCC has nobody to ask in a daemon's session. An agent runs as the logged-in
# user, with the permission that user already granted — which is why this needs
# the Mac to log in by itself after a reboot, and why that is checked below
# rather than left as a surprise on a Sunday morning.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS="$HOME/Library/LaunchAgents"
SERVICES=(livekit token host)
DOMAIN="gui/$(id -u)"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
ok()   { printf '  \033[32m.\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31mx\033[0m %s\n' "$1"; }

usage() { echo "usage: $0 [install|uninstall|status]" >&2; exit 2; }

# node is often version-managed (nvm, fnm, asdf), which puts it under the home
# directory and on PATH via a shell profile that launchd does not read. This
# script does run from a shell that has it, so the resolved path is recorded now
# rather than guessed at boot. Re-run this after changing node versions.
record_node() {
    local current found
    current="$(grep -E '^BELTPACK_NODE_BIN=' "$REPO/.env" 2>/dev/null | sed -E 's/^[^=]*="?([^"]*)"?.*/\1/' || true)"
    [[ -n "$current" && -x "$current" ]] && return 0

    found="$(command -v node || true)"
    if [[ -z "$found" ]]; then
        warn "node not found — the token service will not start"
        return 0
    fi

    if grep -qE '^BELTPACK_NODE_BIN=' "$REPO/.env"; then
        # A literal replacement, so a path with slashes cannot break the
        # expression the way sed's default delimiter would.
        awk -v v="$found" '/^BELTPACK_NODE_BIN=/ { print "BELTPACK_NODE_BIN=\"" v "\""; next } { print }' \
            "$REPO/.env" > "$REPO/.env.tmp" && mv "$REPO/.env.tmp" "$REPO/.env"
    else
        printf '\nBELTPACK_NODE_BIN="%s"\n' "$found" >> "$REPO/.env"
    fi
    ok "node at $found"
}

install_agents() {
    [[ -f "$REPO/.env" ]] || { echo "No .env yet. Run: ./scripts/setup.sh --lan" >&2; exit 1; }

    local host_bin="$REPO/mac/build/Build/Products/Debug/BeltpackHost.app/Contents/MacOS/BeltpackHost"
    if [[ ! -x "$host_bin" ]]; then
        warn "the host app is not built yet — run 'make mac' first, or it will"
        warn "restart-loop until you do"
    fi

    mkdir -p "$AGENTS" "$REPO/logs"
    record_node

    bold "Installing"
    for svc in "${SERVICES[@]}"; do
        local plist="$AGENTS/org.beltpack.$svc.plist"
        local label="$DOMAIN/org.beltpack.$svc"
        local wanted
        wanted="$(sed "s|REPO|$REPO|g" "$REPO/deploy/launchd/org.beltpack.$svc.plist")"

        # Re-running with nothing changed is the common case — after a rebuild,
        # or just to check. Restarting in place skips tearing the job down,
        # which is the part that has to be waited out.
        if [[ -f "$plist" ]] && [[ "$wanted" == "$(cat "$plist")" ]] \
            && launchctl print "$label" >/dev/null 2>&1; then
            launchctl kickstart -k "$label" >/dev/null 2>&1 || true
            ok "org.beltpack.$svc (restarted)"
            continue
        fi

        printf '%s\n' "$wanted" > "$plist"
        launchctl bootout "$label" 2>/dev/null || true

        # Booting out a running job leaves the label unusable for a few
        # seconds, and bootstrapping into that window fails with "Input/output
        # error" — which reads like a failing disk rather than "not yet".
        # launchctl reports the label as gone well before it can be reused, so
        # there is nothing to poll for: this waits.
        local loaded=false
        for _ in $(seq 1 20); do
            if launchctl bootstrap "$DOMAIN" "$plist" 2>/dev/null; then
                loaded=true
                break
            fi
            sleep 0.5
        done

        if $loaded; then
            ok "org.beltpack.$svc"
        else
            bad "could not load org.beltpack.$svc"
            launchctl bootstrap "$DOMAIN" "$plist" || true
            exit 1
        fi
    done

    echo
    check_autologin
    echo
    bold "Checking"
    verify
}

uninstall_agents() {
    bold "Removing"
    for svc in "${SERVICES[@]}"; do
        local label="$DOMAIN/org.beltpack.$svc"

        # Keep asking until it is actually gone. A single bootout can fail
        # while the job is busy restarting itself, and deleting the plist on
        # top of that leaves it loaded with nothing on disk to explain it —
        # a service still holding its port that no file accounts for.
        local gone=false
        for _ in $(seq 1 20); do
            if ! launchctl print "$label" >/dev/null 2>&1; then
                gone=true
                break
            fi
            launchctl bootout "$label" 2>/dev/null || true
            sleep 0.5
        done

        rm -f "$AGENTS/org.beltpack.$svc.plist"

        if $gone; then
            ok "org.beltpack.$svc"
        else
            bad "org.beltpack.$svc is still loaded — run: launchctl bootout $label"
        fi
    done
}

# An agent runs at login, not at boot. Without automatic login a rebooted Mac
# sits at the login window with nothing running, which looks exactly like the
# agents not being installed.
check_autologin() {
    bold "Automatic login"
    local user
    user="$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true)"
    if [[ -n "$user" ]]; then
        ok "enabled for '$user'"
        if fdesetup status 2>/dev/null | grep -q "FileVault is On"; then
            warn "FileVault is on, so the disk still needs unlocking by hand after"
            warn "a reboot before that login happens"
        fi
    else
        warn "not enabled — these start at login, so a rebooted Mac will sit at"
        warn "the login window with comms down"
        warn "System Settings > Users & Groups > Automatically log in as"
    fi
}

verify() {
    local port failures=0
    # shellcheck disable=SC1091
    set -a; source "$REPO/.env"; set +a

    for entry in "livekit:7880" "token:${TOKEN_PORT:-7883}" "control:${BELTPACK_ADMIN_PORT:-7884}"; do
        local name="${entry%%:*}" port="${entry##*:}"
        local up=false
        for _ in $(seq 1 40); do
            if curl -s -o /dev/null -m 1 "http://127.0.0.1:$port/"; then up=true; break; fi
        done
        if $up; then ok "$name on $port"; else bad "$name not answering on $port"; failures=$((failures + 1)); fi
    done

    if (( failures > 0 )); then
        echo
        if ! pgrep -x BeltpackHost >/dev/null; then
            # There is no menu bar icon until the app runs, so pointing at one
            # sends somebody looking for something that is not there.
            warn "the host app is not running, so there is no menu bar icon yet"
            warn "build it with 'make mac', then re-run this"
        fi
        warn "logs: make logs, make mac-logs-past SINCE=10m, or logs/bridge.log"
        return 1
    fi
}

status_agents() {
    bold "Agents"
    for svc in "${SERVICES[@]}"; do
        if launchctl print "$DOMAIN/org.beltpack.$svc" >/dev/null 2>&1; then
            ok "org.beltpack.$svc loaded"
        else
            bad "org.beltpack.$svc not loaded"
        fi
    done
    echo
    check_autologin
    echo
    bold "Ports"
    verify || true
}

case "${1:-install}" in
    install) install_agents ;;
    uninstall) uninstall_agents ;;
    status) status_agents ;;
    *) usage ;;
esac
