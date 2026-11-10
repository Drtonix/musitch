#!/bin/bash
# musitch — сборка нативного .app и установка в /Applications.
# Требует: Xcode.app (тулчейн), icon/icon_1024.png уже сгенерирован.
set -euo pipefail
cd "$(dirname "$0")"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

echo "==> swift build -c release"
swift build -c release

BIN=".build/release/musitch"
APP="musitch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/musitch"

echo "==> иконка"
rm -rf icon/musitch.iconset
mkdir icon/musitch.iconset
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" icon/icon_1024.png \
    --out "icon/musitch.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" icon/icon_1024.png \
    --out "icon/musitch.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns icon/musitch.iconset -o icon/musitch.icns
cp icon/musitch.icns "$APP/Contents/Resources/musitch.icns"

echo "==> ffmpeg для mp3/ogg/flac"
FF=""
for cand in /Users/tonix/Developer/severance/build/tools/ffmpeg \
            /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
  if [ -x "$cand" ]; then FF="$cand"; break; fi
done
if [ -n "$FF" ]; then
  cp "$FF" "$APP/Contents/Resources/ffmpeg"
  echo "    взяли $FF"
else
  echo "    ffmpeg не найден — экспорт только в WAV"
fi

echo "==> Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>musitch</string>
  <key>CFBundleIdentifier</key><string>com.drtonix.musitch</string>
  <key>CFBundleName</key><string>musitch</string>
  <key>CFBundleDisplayName</key><string>musitch</string>
  <key>CFBundleIconFile</key><string>musitch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> adhoc-подпись"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"

echo "==> установка в /Applications"
ditto "$APP" "/Applications/musitch.app"
xattr -dr com.apple.quarantine "/Applications/musitch.app" 2>/dev/null || true

echo "==> готово: /Applications/musitch.app"
