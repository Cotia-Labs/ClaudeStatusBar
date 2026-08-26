#!/bin/bash
# Compila e empacota ClaudeStatusBar.app em ./dist.
#
#   ./build-app.sh              build para a arquitetura local
#   ./build-app.sh --universal  binário universal (arm64 + x86_64)
#   ./build-app.sh --dmg        gera também dist/ClaudeStatusBar-<versão>.dmg
#   ./build-app.sh --install    copia o .app para /Applications
#
# Variáveis de ambiente:
#   SIGNING_IDENTITY        assina com Developer ID em vez de ad-hoc
#   SPARKLE_PUBLIC_ED_KEY   chave pública EdDSA; sem ela o app é empacotado
#                           sem o feed do Sparkle e cai no aviso via GitHub
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

# Traduções: Localization.swift resolve as chaves em Contents/Resources.
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "$APP/Contents/Resources/"
done

# Sparkle: o framework vem do artefato baixado pelo SwiftPM (fatia universal),
# e o binário procura por @executable_path/../Frameworks (ver Package.swift).
# O `--universal` compila com --scratch-path, então o artefato pode estar em
# .build/artifacts ou em .build/<arch>/artifacts; procurar cobre os dois casos.
SPARKLE_FRAMEWORK="$(find .build -type d \
    -path "*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" -print -quit 2>/dev/null || true)"
if [ -z "$SPARKLE_FRAMEWORK" ] || [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "Sparkle.framework não encontrado em .build" >&2
    echo "Rode 'swift build' uma vez para o SwiftPM baixar o artefato." >&2
    exit 1
fi
mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"

# O feed só entra quando existe chave pública para validar a assinatura do
# update. Sem ela o Updater se declara indisponível e o app usa o aviso antigo.
if [ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]; then
    PLIST="$APP/Contents/Info.plist"
    plutil -insert SUFeedURL -string \
        "https://raw.githubusercontent.com/Cotia-Labs/ClaudeStatusBar/main/appcast.xml" "$PLIST"
    plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$PLIST"
    plutil -insert SUEnableAutomaticChecks -bool true "$PLIST"
    plutil -insert SUScheduledCheckInterval -integer 86400 "$PLIST"
    echo "Sparkle habilitado (appcast + chave pública)."
else
    echo "SPARKLE_PUBLIC_ED_KEY ausente: app empacotado sem auto-update."
fi

# Com SIGNING_IDENTITY (ex.: "Developer ID Application: Cotia Labs (TEAMID)")
# a assinatura sai com hardened runtime e timestamp, pronta para notarização.
# Sem ela, cai na assinatura ad-hoc: roda localmente, mas o Gatekeeper pede a
# primeira abertura pelo menu contextual (ver README).
IDENTITY="${SIGNING_IDENTITY:--}"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ "$IDENTITY" = "-" ]; then
    SIGN_ARGS=(--force --sign -)
else
    SIGN_ARGS=(--force --options runtime --timestamp --sign "$IDENTITY")
fi

# `--deep` não serve aqui: os helpers do Sparkle precisam ser assinados antes
# do framework, e o framework antes do app, ou o Gatekeeper rejeita o bundle.
codesign "${SIGN_ARGS[@]}" "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGN_ARGS[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
codesign "${SIGN_ARGS[@]}" "$SPARKLE/Versions/B/Autoupdate"
codesign "${SIGN_ARGS[@]}" "$SPARKLE/Versions/B/Updater.app"
codesign "${SIGN_ARGS[@]}" "$SPARKLE"
codesign "${SIGN_ARGS[@]}" "$APP"

if [ "$IDENTITY" = "-" ]; then
    echo "Assinado ad-hoc (sem Developer ID)."
else
    codesign --verify --strict --verbose=1 "$APP"
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
