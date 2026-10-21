#!/bin/bash
# Instala (ou atualiza) o ClaudeStatusBar a partir da última Release do GitHub.
#
#   curl -fsSL https://raw.githubusercontent.com/Cotia-Labs/ClaudeStatusBar/main/scripts/install.sh | bash
#
# Passos: baixa o .dmg mais recente, monta, encerra a versão em execução,
# copia o app para /Applications, remove a quarentena (o app é assinado só
# ad-hoc, então sem isso o Gatekeeper o bloqueia), desmonta e abre.
#
# Variáveis de ambiente opcionais:
#   VERSION   tag específica a instalar (ex.: v1.0.11); padrão: a mais recente
#   DEST_DIR  pasta de destino; padrão: /Applications
set -euo pipefail

REPO="Cotia-Labs/ClaudeStatusBar"
APP_NAME="ClaudeStatusBar.app"
DEST_DIR="${DEST_DIR:-/Applications}"
DEST="$DEST_DIR/$APP_NAME"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mErro:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "este instalador é só para macOS."

# macOS 13+ é o mínimo do Package.swift.
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 13 ] || fail "requer macOS 13 ou mais recente (encontrado $(sw_vers -productVersion))."

# Diretório temporário e ponto de montagem limpos em qualquer saída.
tmp="$(mktemp -d)"
mnt=""
cleanup() {
    [ -n "$mnt" ] && hdiutil detach -quiet "$mnt" 2>/dev/null || true
    rm -rf "$tmp"
}
trap cleanup EXIT

if [ -n "${VERSION:-}" ]; then
    api="https://api.github.com/repos/$REPO/releases/tags/$VERSION"
else
    api="https://api.github.com/repos/$REPO/releases/latest"
fi

info "Procurando a release ${VERSION:-mais recente}..."
url="$(curl -fsSL "$api" \
    | grep -o '"browser_download_url": *"[^"]*\.dmg"' \
    | head -n1 | cut -d '"' -f4)" || true
[ -n "$url" ] || fail "nenhum .dmg encontrado em $api"

info "Baixando $(basename "$url")..."
curl -fL --progress-bar "$url" -o "$tmp/ClaudeStatusBar.dmg"

info "Montando a imagem..."
mnt="$(hdiutil attach -nobrowse -readonly -noautoopen "$tmp/ClaudeStatusBar.dmg" \
    | awk -F '\t' '/\/Volumes\// {print $NF; exit}')"
[ -d "$mnt/$APP_NAME" ] || fail "$APP_NAME não encontrado dentro do DMG."

# Um app em execução não pode ser sobrescrito com segurança.
if pgrep -x ClaudeStatusBar >/dev/null 2>&1; then
    info "Encerrando a versão em execução..."
    osascript -e 'quit app "ClaudeStatusBar"' 2>/dev/null || pkill -x ClaudeStatusBar || true
    sleep 2
fi

# Usa sudo só quando o destino não é gravável pelo usuário atual.
SUDO=""
if [ ! -w "$DEST_DIR" ] || { [ -e "$DEST" ] && [ ! -w "$DEST" ]; }; then
    info "Precisa da sua senha para escrever em $DEST_DIR."
    SUDO="sudo"
fi

info "Copiando para $DEST..."
$SUDO rm -rf "$DEST"
$SUDO ditto "$mnt/$APP_NAME" "$DEST"
$SUDO xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

info "Abrindo..."
open "$DEST"

printf '\n\033[1;32m✓ Pronto!\033[0m O ícone aparece na barra de menus, no topo da tela.\n'
printf '  Requer login ativo do Claude Code (claude auth).\n'
