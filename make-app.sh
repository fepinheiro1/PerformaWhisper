#!/bin/zsh
# Builds PerformaWhisper.app from the SwiftPM release build.
set -e
cd "$(dirname "$0")"

echo "→ Compilando (release)…"
swift build -c release

APP="build/PerformaWhisper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/PerformaWhisper "$APP/Contents/MacOS/PerformaWhisper"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>PerformaWhisper</string>
    <key>CFBundleIdentifier</key>
    <string>com.pinheiro.performawhisper</string>
    <key>CFBundleName</key>
    <string>PerformaWhisper</string>
    <key>CFBundleDisplayName</key>
    <string>PerformaWhisper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>O PerformaWhisper usa o microfone para transcrever sua voz localmente.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so TCC (mic/accessibility) permissions persist.
# No --deep: it is deprecated and the bundle has no nested code anyway.
codesign --force --sign - "$APP"

echo "✓ Pronto: $PWD/$APP"
echo "  Mova para /Applications se quiser: cp -r $APP /Applications/"
