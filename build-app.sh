#!/bin/bash
# Compila e empacota ClaudeStatusBar.app em ./dist (e instala em /Applications com --install).
set -euo pipefail

cd "$(dirname "$0")"
APP="dist/ClaudeStatusBar.app"

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClaudeStatusBar "$APP/Contents/MacOS/ClaudeStatusBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Assinatura ad-hoc: suficiente para notificações locais e "abrir no login".
codesign --force --deep --sign - "$APP"
echo "Gerado: $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/ClaudeStatusBar.app
    cp -R "$APP" /Applications/
    echo "Instalado em /Applications/ClaudeStatusBar.app"
fi
