#!/bin/bash
# Compila e empacota ClaudeStatusBar.app em ./dist.
#
#   ./build-app.sh              build para a arquitetura local
#   ./build-app.sh --universal  binário universal (arm64 + x86_64)
#   ./build-app.sh --dmg        gera também dist/ClaudeStatusBar-<versão>.dmg
#   ./build-app.sh --install    copia o .app para /Applications
#
# As flags podem ser combinadas.
set -euo pipefail

cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="${GITHUB_RUN_NUMBER:-1}"
APP="dist/ClaudeStatusBar.app"
DMG="dist/ClaudeStatusBar-${VERSION}.dmg"

universal=false
make_dmg=false
install=false
for arg in "$@"; do
    case "$arg" in
        --universal) universal=true ;;
        --dmg) make_dmg=true ;;
        --install) install=true ;;
        *) echo "Flag desconhecida: $arg" >&2; exit 2 ;;
    esac
done

if $universal; then
    # `swift build --arch a --arch b` exige o Xcode completo (xcbuild); um build
    # por triple + lipo funciona também com as Command Line Tools.
    swift build -c release --triple arm64-apple-macosx13.0 --scratch-path .build/arm64
    swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path .build/x86_64
    binary=".build/universal/ClaudeStatusBar"
    mkdir -p .build/universal
    lipo -create -output "$binary" \
        .build/arm64/release/ClaudeStatusBar \
        .build/x86_64/release/ClaudeStatusBar
else
    swift build -c release
    binary=".build/release/ClaudeStatusBar"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$binary" "$APP/Contents/MacOS/ClaudeStatusBar"
sed -e "s/__VERSION__/${VERSION}/" -e "s/__BUILD__/${BUILD}/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
# O ícone é referenciado pelo Info.plist como CFBundleIconFile = AppIcon.
cp logo.icns "$APP/Contents/Resources/AppIcon.icns"

# Com SIGNING_IDENTITY (ex.: "Developer ID Application: Cotia Labs (TEAMID)")
# a assinatura sai com hardened runtime e timestamp, pronta para notarização.
# Sem ela, cai na assinatura ad-hoc: roda localmente, mas o Gatekeeper pede a
# primeira abertura pelo menu contextual (ver README).
IDENTITY="${SIGNING_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP"
    echo "Assinado ad-hoc (sem Developer ID)."
else
    codesign --force --deep --options runtime --timestamp \
        --sign "$IDENTITY" "$APP"
    codesign --verify --strict --deep "$APP"
    echo "Assinado com: $IDENTITY"
fi
echo "Gerado: $APP (versão ${VERSION}, build ${BUILD})"

if $make_dmg; then
    rm -f "$DMG"
    staging="$(mktemp -d)"
    cp -R "$APP" "$staging/"
    ln -s /Applications "$staging/Applications"

    # Ícone do próprio volume montado.
    cp logo.icns "$staging/.VolumeIcon.icns"
    SetFile -a C "$staging" 2>/dev/null || true

    hdiutil create -volname "Claude Status ${VERSION}" \
        -srcfolder "$staging" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$staging"
    echo "Gerado: $DMG"
fi

if $install; then
    rm -rf /Applications/ClaudeStatusBar.app
    cp -R "$APP" /Applications/
    echo "Instalado em /Applications/ClaudeStatusBar.app"
fi
