#!/usr/bin/env bash
#
# Build for device and install on every connected iPhone.
#
# Passing --allowProvisioningUpdates is not optional here. Without it, signing
# silently falls back to any wildcard profile lying around in Xcode's cache —
# including one from a team this app has nothing to do with. The phone still
# installs, and the watch app dies the instant it is tapped, with no crash log
# on this machine to explain why. So the signature is checked before anything
# is installed.
set -euo pipefail

cd "$(dirname "$0")/.."
DERIVED=${BELTPACK_DERIVED:-/tmp/bp-dev}
APP="$DERIVED/Build/Products/Debug-iphoneos/Beltpack.app"

echo "==> Generating project"
(cd ios && xcodegen generate >/dev/null)

echo "==> Building for device"
# The build output goes to a log rather than through a pipe: piping it into
# grep and tolerating grep's empty-match exit status would also swallow
# xcodebuild's, and a failed build would then quietly install whatever stale
# bundle was still on disk.
log=$(mktemp -t beltpack-build)
if ! (cd ios && xcodebuild -project Beltpack.xcodeproj -scheme Beltpack \
        -configuration Debug -destination 'generic/platform=iOS' \
        -derivedDataPath "$DERIVED" -allowProvisioningUpdates build) \
        >"$log" 2>&1; then
    grep -E "error:" "$log" | sort -u | head -20 >&2
    echo >&2
    echo "build failed — full log at $log" >&2
    exit 1
fi
rm -f "$log"

[ -d "$APP" ] || { echo "build produced no app at $APP" >&2; exit 1; }

# ---- verify the signature before trusting it ------------------------------

prefix() {
    codesign -d --entitlements :- "$1" 2>/dev/null \
        | plutil -extract application-identifier raw - 2>/dev/null \
        | cut -d. -f1
}

phone_team=$(prefix "$APP")
echo "==> Phone signed by team ${phone_team:-<none>}"

watch="$APP/Watch/BeltpackWatch.app"
if [ -d "$watch" ]; then
    watch_team=$(prefix "$watch")
    echo "==> Watch signed by team ${watch_team:-<none>}"
    if [ "$watch_team" != "$phone_team" ]; then
        cat >&2 <<MSG

REFUSING TO INSTALL: the watch app is signed by team '$watch_team' but the
phone app by '$phone_team'. watchOS will install this pair and then kill the
watch app at launch — it looks like a crash with no crash report.

This means no provisioning profile exists for
org.beltpack.Beltpack.watchkitapp under team $phone_team, so signing fell back
to a wildcard profile from another team. Creating one needs your Apple ID:

  1. open ios/Beltpack.xcodeproj in Xcode
  2. select the BeltpackWatch target -> Signing & Capabilities
  3. confirm the team, and let Xcode register the App ID
  4. re-run this script

MSG
        exit 1
    fi
else
    echo "    (no watch app embedded)" >&2
fi

# ---- install ---------------------------------------------------------------

devices=$(mktemp)
trap 'rm -f "$devices"' EXIT
xcrun devicectl list devices --json-output "$devices" >/dev/null 2>&1 || true

ids=$(python3 - "$devices" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit(0)
for d in devices:
    props = d.get("deviceProperties", {})
    hardware = d.get("hardwareProperties", {})
    if hardware.get("platform") != "iOS":
        continue
    if d.get("connectionProperties", {}).get("tunnelState") == "unavailable":
        continue
    print(f'{d["identifier"]}\t{props.get("name", "?")}')
PY
)

[ -n "$ids" ] || { echo "no connected iPhone found — pair one in Xcode first"; exit 0; }

while IFS=$'\t' read -r id name; do
    [ -n "$id" ] || continue
    echo "==> Installing on $name"
    xcrun devicectl device install app --device "$id" "$APP" 2>&1 \
        | grep -E "App installed|error|Error" || true
done <<< "$ids"
