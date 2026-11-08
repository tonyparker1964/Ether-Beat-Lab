#!/bin/sh
# Builds Ether Beat Lab for Mac and puts "Ether Beat Lab.app" in your Applications folder.
# Run it again after pulling updates to install the new version.
set -e
cd "$(dirname "$0")"
ROOT="$(pwd)"

echo "Building Ether Beat Lab (release). The first build takes a minute or two…"
cd mac
swift build -c release --product EtherBeatLab
BIN="$(swift build -c release --show-bin-path)/EtherBeatLab"
cd "$ROOT"

STAGE="$(mktemp -d)"
APP="$STAGE/Ether Beat Lab.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Web"
cp "$BIN" "$APP/Contents/MacOS/EtherBeatLab"
cp mac/Info.plist "$APP/Contents/Info.plist"
cp index.html "$APP/Contents/Resources/Web/index.html"

ICONSET="$STAGE/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size mac/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double mac/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

DEST="/Applications/Ether Beat Lab.app"
if pgrep -x EtherBeatLab >/dev/null; then
  osascript -e 'quit app "Ether Beat Lab"' >/dev/null 2>&1 || pkill -x EtherBeatLab || true
  sleep 1
fi
rm -rf "$DEST"
ditto "$APP" "$DEST"
rm -rf "$STAGE"
touch "$DEST"
echo "Installed: $DEST"
open "$DEST"
