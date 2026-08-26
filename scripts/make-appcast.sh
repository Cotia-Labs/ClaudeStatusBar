#!/bin/bash
# Gera/atualiza o appcast.xml que o Sparkle consulta.
#
#   SPARKLE_PRIVATE_ED_KEY="…" ./scripts/make-appcast.sh dist/ClaudeStatusBar-1.0.9.dmg
#
# A chave privada EdDSA vem do `generate_keys` do Sparkle (ver README). Ela
# assina o DMG; o app valida com a pública gravada no Info.plist. Sem o par de
# chaves não há auto-update — e é por isso que ele é opcional no build.
set -euo pipefail

cd "$(dirname "$0")/.."

DMG="${1:-}"
if [ ! -f "$DMG" ]; then
    echo "uso: $0 <caminho do .dmg>" >&2
    exit 2
fi
if [ -z "${SPARKLE_PRIVATE_ED_KEY:-}" ]; then
    echo "SPARKLE_PRIVATE_ED_KEY não definida." >&2
    exit 2
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
SPARKLE_VERSION="${SPARKLE_TOOLS_VERSION:-2.9.6}"
REPO="Cotia-Labs/ClaudeStatusBar"

# As ferramentas (generate_appcast, generate_keys, sign_update) só saem no
# tarball de release do Sparkle, não no pacote SwiftPM.
tools="$(mktemp -d)"
trap 'rm -rf "$tools"' EXIT
curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
    | tar -xJ -C "$tools"

keyfile="$tools/ed_private_key"
printf '%s' "$SPARKLE_PRIVATE_ED_KEY" > "$keyfile"
chmod 600 "$keyfile"

# generate_appcast varre um diretório inteiro e preserva as entradas antigas do
# appcast que já estiver lá, então basta jogar o DMG novo num staging limpo.
staging="$tools/updates"
mkdir -p "$staging"
cp "$DMG" "$staging/"
[ -f appcast.xml ] && cp appcast.xml "$staging/appcast.xml"

"$tools/bin/generate_appcast" \
    --ed-key-file "$keyfile" \
    --download-url-prefix "https://github.com/${REPO}/releases/download/v${VERSION}/" \
    --link "https://github.com/${REPO}" \
    --full-release-notes-url "https://github.com/${REPO}/blob/main/CHANGELOG.md" \
    "$staging"

cp "$staging/appcast.xml" appcast.xml
echo "Gerado: appcast.xml (versão ${VERSION})"
