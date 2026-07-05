#!/bin/zsh
# Builds WhisperFlow.app from the SwiftPM release build.
set -e
cd "$(dirname "$0")"

echo "→ Compilando (release)…"
swift build -c release

APP="build/WhisperFlow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/WhisperFlow "$APP/Contents/MacOS/WhisperFlow"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WhisperFlow</string>
    <key>CFBundleIdentifier</key>
    <string>com.pinheiro.whisperflow</string>
    <key>CFBundleName</key>
    <string>WhisperFlow</string>
    <key>CFBundleDisplayName</key>
    <string>WhisperFlow</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>O WhisperFlow usa o microfone para transcrever sua voz localmente.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so TCC (mic/accessibility) permissions persist.
codesign --force --deep --sign - "$APP"

echo "✓ Pronto: $PWD/$APP"
echo "  Mova para /Applications se quiser: cp -r $APP /Applications/"
