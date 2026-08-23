#!/bin/bash
# Regenerates every app icon from one source image.
#
# Generated icons are committed because they are build inputs, but they are
# never edited by hand: change appicon-raw.png and run this. Uses sips, which
# ships with macOS, so there is nothing to install.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$REPO/appicon-raw.png"

[[ -f "$SOURCE" ]] || { echo "make-icons: $SOURCE not found" >&2; exit 1; }

# iOS rejects an icon with an alpha channel, and the failure arrives at upload
# time rather than build time.
if [[ "$(sips -g hasAlpha "$SOURCE" | tail -1 | awk '{print $2}')" == "yes" ]]; then
  echo "make-icons: $SOURCE has an alpha channel; flatten it first." >&2
  exit 1
fi

emit() { # emit <size> <destination>
  sips -s format png -z "$1" "$1" "$SOURCE" --out "$2" >/dev/null
}

# ---- iOS and watchOS ------------------------------------------------------
# Both take a single 1024 and let the system produce the rest.
IOS_SET="$REPO/ios/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$IOS_SET"
emit 1024 "$IOS_SET/icon-1024.png"

cat > "$REPO/ios/Resources/Assets.xcassets/Contents.json" <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON

cat > "$IOS_SET/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "watchos", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

# ---- macOS ----------------------------------------------------------------
# macOS still wants every size baked, unlike iOS.
MAC_SET="$REPO/mac/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$MAC_SET"
for size in 16 32 64 128 256 512 1024; do
  emit "$size" "$MAC_SET/icon-$size.png"
done

cat > "$REPO/mac/Resources/Assets.xcassets/Contents.json" <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON

cat > "$MAC_SET/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon-16.png",   "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon-32.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon-32.png",   "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon-64.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon-128.png",  "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon-256.png",  "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon-256.png",  "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon-512.png",  "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon-512.png",  "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon-1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

# ---- web ------------------------------------------------------------------
WEB="$REPO/web/icons"
mkdir -p "$WEB"
emit 192 "$WEB/icon-192.png"
emit 512 "$WEB/icon-512.png"
emit 180 "$WEB/apple-touch-icon.png"

echo "icons regenerated from $(basename "$SOURCE")"
