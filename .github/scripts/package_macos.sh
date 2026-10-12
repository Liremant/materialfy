#!/usr/bin/env bash
# macOS packaging: Materialfy.app + .dmg via macdeployqt.
#
#   QMAKE=~/Qt/6.12.0/macos/bin/qmake6 .github/scripts/package_macos.sh 0.1.0
#
# Contents/MacOS: materialfy, qml/, assets/ (the shell looks for <exe>/qml). Audio is librespot/cpal
# (CoreAudio) inside the executable, there are no external player libraries. The .icns icon is built
# from materialfy.png (512 px). The dmg name carries the architecture of the built executable.
set -euo pipefail

VERSION="${1:?usage: package_macos.sh VERSION}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXE="${MATERIALFY_EXE:-$ROOT/target/release/materialfy}"
OUT="$ROOT/target/dist"
APP="$OUT/Materialfy.app"
: "${QMAKE:?QMAKE must point to qmake6 from Qt 6.12}"
QTBIN="$("$QMAKE" -query QT_INSTALL_BINS)"
ARCH="${MATERIALFY_ARCH:-$(uname -m)}"

[ -x "$EXE" ] || { echo "$EXE not found" >&2; exit 1; }
# only this architecture's dmg: CI packages arm64 and x86_64 one after the other into the same folder
rm -rf "$APP" "$OUT/Materialfy-$VERSION-macos-$ARCH.dmg"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

install -m755 "$EXE" "$APP/Contents/MacOS/materialfy"
cp -R "$ROOT/src/materialfy/qml" "$APP/Contents/MacOS/qml"
find "$APP/Contents/MacOS/qml" -name __pycache__ -prune -exec rm -rf {} +
mkdir -p "$APP/Contents/MacOS/assets"
cp -R "$ROOT/src/materialfy/assets/fonts" "$APP/Contents/MacOS/assets/fonts"
find "$ROOT/src/materialfy/assets" -maxdepth 1 -type f \( -name '*.svg' -o -name '*.png' \) \
    -exec cp {} "$APP/Contents/MacOS/assets/" \;

# .icns from a PNG set of the logo (sips and iconutil ship with every macOS)
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
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSLocalNetworkUsageDescription</key><string>Spotify Connect: discovering devices on the local network.</string>
  <key>NSBonjourServices</key><array><string>_spotify-connect._tcp</string></array>
</dict>
</plist>
PLIST

"$QTBIN/macdeployqt" "$APP" -qmldir="$ROOT/src/materialfy/qml" -always-overwrite
# --screenshot renders with the offscreen platform; macdeployqt only ships cocoa
QTPLUGINS="$("$QTBIN/qmake6" -query QT_INSTALL_PLUGINS 2>/dev/null || "$QTBIN/qmake" -query QT_INSTALL_PLUGINS)"
if [ -f "$QTPLUGINS/platforms/libqoffscreen.dylib" ]; then
    cp "$QTPLUGINS/platforms/libqoffscreen.dylib" "$APP/Contents/PlugIns/platforms/"
    install_name_tool -add_rpath "@loader_path/../../Frameworks" "$APP/Contents/PlugIns/platforms/libqoffscreen.dylib" 2>/dev/null || true
fi
# macdeployqt rewrites the binaries - ad hoc signature, otherwise arm64 refuses to launch it
codesign --force --deep --sign - "$APP"

DMG="$OUT/Materialfy-$VERSION-macos-$ARCH.dmg"
# hdiutil occasionally fails with "Resource busy" on CI runners - retry a few times
for i in 1 2 3 4 5; do
    if hdiutil create -volname "Materialfy" -srcfolder "$APP" -ov -format UDZO "$DMG"; then
        break
    fi
    [ "$i" -eq 5 ] && { echo "hdiutil failed" >&2; exit 1; }
    sleep $((i * 5))
done
echo "dmg: $DMG"
