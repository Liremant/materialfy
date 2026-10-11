#!/usr/bin/env bash
# Упаковка macOS (best effort): Materialfy.app + .dmg через macdeployqt.
#
#   QMAKE=~/Qt/6.12.0/macos/bin/qmake6 .github/scripts/package_macos.sh 0.1.0
#
# Contents/MacOS: materialfy, qml/, assets/ (оболочка ищет <exe>/qml). Звук — librespot/cpal (CoreAudio)
# внутри exe, внешних библиотек плеера нет. Значок .icns собирается из materialfy.png (512 px).
set -euo pipefail

VERSION="${1:?версия}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXE="${MATERIALFY_EXE:-$ROOT/target/release/materialfy}"
OUT="$ROOT/target/dist"
APP="$OUT/Materialfy.app"
: "${QMAKE:?нужен QMAKE (путь к qmake6 из Qt 6.12)}"
QTBIN="$("$QMAKE" -query QT_INSTALL_BINS)"

[ -x "$EXE" ] || { echo "нет $EXE" >&2; exit 1; }
rm -rf "$APP" "$OUT"/Materialfy*.dmg
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

install -m755 "$EXE" "$APP/Contents/MacOS/materialfy"
cp -R "$ROOT/src/materialfy/qml" "$APP/Contents/MacOS/qml"
find "$APP/Contents/MacOS/qml" -name __pycache__ -prune -exec rm -rf {} +
mkdir -p "$APP/Contents/MacOS/assets"
cp -R "$ROOT/src/materialfy/assets/fonts" "$APP/Contents/MacOS/assets/fonts"
find "$ROOT/src/materialfy/assets" -maxdepth 1 -type f \( -name '*.svg' -o -name '*.png' \) \
    -exec cp {} "$APP/Contents/MacOS/assets/" \;

# .icns из PNG-набора логотипа (sips + iconutil есть в любой macOS)
ICONSET="$OUT/materialfy.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
SRC_PNG="$ROOT/materialfy.png"
for s in 16 32 128 256; do
    sips -z "$s" "$s" "$SRC_PNG" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    [ "$d" -le 256 ] && sips -z "$d" "$d" "$SRC_PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/materialfy.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Materialfy</string>
  <key>CFBundleDisplayName</key><string>Materialfy</string>
  <key>CFBundleIdentifier</key><string>io.github.materialfy</string>
  <key>CFBundleExecutable</key><string>materialfy</string>
  <key>CFBundleIconFile</key><string>materialfy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSLocalNetworkUsageDescription</key><string>Spotify Connect: поиск устройств в локальной сети.</string>
  <key>NSBonjourServices</key><array><string>_spotify-connect._tcp</string></array>
</dict>
</plist>
PLIST

"$QTBIN/macdeployqt" "$APP" -qmldir="$ROOT/src/materialfy/qml" -always-overwrite
# macdeployqt правит бинарники — подпись ad hoc, иначе arm64 не запустит
codesign --force --deep --sign - "$APP"

DMG="$OUT/Materialfy-$VERSION-macos-$(uname -m).dmg"
hdiutil create -volname "Materialfy" -srcfolder "$APP" -ov -format UDZO "$DMG"
echo "dmg: $DMG"
