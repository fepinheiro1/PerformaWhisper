#!/bin/zsh
# Builds PerformaWhisper.app from the SwiftPM release build.
set -e
cd "$(dirname "$0")"

# Binário universal: um .app só que roda em Apple Silicon e em Macs Intel.
# Cada arquitetura é compilada em separado com --triple e depois unida com lipo,
# porque `swift build --arch a --arch b` exige o Xcode completo, e aqui as
# Command Line Tools bastam.
DEPLOY_TARGET="13.0"
ARM_BIN=".build/arm64-apple-macosx/release/PerformaWhisper"
X86_BIN=".build/x86_64-apple-macosx/release/PerformaWhisper"
BUILT_ARCHS=()

for arch in arm64 x86_64; do
    echo "→ Compilando release para $arch…"
    if swift build -c release --triple "${arch}-apple-macosx${DEPLOY_TARGET}"; then
        BUILT_ARCHS+=("$arch")
    else
        echo "  ⚠️  Falhou para $arch — seguindo sem essa arquitetura."
    fi
done

if [ ${#BUILT_ARCHS[@]} -eq 0 ]; then
    echo "✗ Nenhuma arquitetura compilou. Abortando."
    exit 1
fi

APP="build/PerformaWhisper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ ${#BUILT_ARCHS[@]} -eq 2 ]; then
    lipo -create "$ARM_BIN" "$X86_BIN" -output "$APP/Contents/MacOS/PerformaWhisper"
    echo "→ Binário universal: $(lipo -archs "$APP/Contents/MacOS/PerformaWhisper")"
else
    # Só uma arquitetura compilou: o .app roda apenas em Macs equivalentes.
    only="${BUILT_ARCHS[1]}"
    [ "$only" = "arm64" ] && cp "$ARM_BIN" "$APP/Contents/MacOS/PerformaWhisper" \
                          || cp "$X86_BIN" "$APP/Contents/MacOS/PerformaWhisper"
    echo "  ⚠️  App gerado só para $only — não vai abrir em Macs de outra arquitetura."
fi

# Os bundles de recurso são iguais nas duas arquiteturas; usa os da primeira que
# compilou.
RES_DIR=".build/${BUILT_ARCHS[1]}-apple-macosx/release"

# Wordmark shown in the onboarding window, loaded via Bundle.main.
cp Assets/logo-light.png Assets/logo-dark.png "$APP/Contents/Resources/"

# Resource bundles from the dependencies, kept in the standard location.
# Note: SwiftPM's generated Bundle.module accessor looks for them beside
# Bundle.main.bundleURL (the .app root), where codesign refuses to seal them,
# and otherwise falls back to an absolute .build path from the build machine.
# In practice the only consumer is swift-transformers' gpt2/t5 fallback
# tokenizer config, which Whisper never asks for — but an .app copied to a Mac
# that did not build it would trap there rather than degrade.
for bundle in "$RES_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# App icon: build the .icns from the 1024px source with the tools that ship
# with macOS, so there is nothing extra to install.
echo "→ Gerando ícone…"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Assets/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Assets/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
