#!/usr/bin/env bash
# Clipboard Manager — instalador via curl
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/Italovini223/mac-clipboard/main/install.sh | bash
#
# O script baixa a versão mais recente do GitHub Releases,
# instala em /Applications e remove o atributo de quarentena.

set -euo pipefail

# ── Configuração ──────────────────────────────────────────────────────────────
GITHUB_REPO="Italovini223/mac-clipboard"
APP_NAME="Clipboard Manager"
INSTALL_DIR="/Applications"
# ─────────────────────────────────────────────────────────────────────────────

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

log()  { echo -e "  ${BOLD}$*${RESET}"; }
ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
err()  { echo -e "  ${RED}✗${RESET} $*" >&2; exit 1; }

echo ""
echo -e "${BOLD}Clipboard Manager — Instalador${RESET}"
echo "────────────────────────────────"

# ── 1. Verificar macOS ────────────────────────────────────────────────────────
OS=$(uname -s)
[[ "$OS" != "Darwin" ]] && err "Este instalador é exclusivo para macOS."

MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if (( MACOS_MAJOR < 14 )); then
    err "Requer macOS 14 (Sonoma) ou superior. Versão atual: $(sw_vers -productVersion)"
fi

# ── 2. Verificar dependências ─────────────────────────────────────────────────
for cmd in curl unzip; do
    command -v "$cmd" &>/dev/null || err "Comando '$cmd' não encontrado."
done

# ── 3. Obter URL da release mais recente ─────────────────────────────────────
log "Verificando última versão no GitHub…"

RELEASE_INFO=$(curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null) \
    || err "Não foi possível acessar GitHub Releases. Verifique sua conexão ou o repositório '${GITHUB_REPO}'."

VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep '"browser_download_url"' | grep '\.zip' | head -1 | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')

[[ -z "$VERSION" ]]      && err "Nenhuma release encontrada em '${GITHUB_REPO}'."
[[ -z "$DOWNLOAD_URL" ]] && err "Nenhum arquivo .zip encontrado na release '${VERSION}'."

ok "Versão encontrada: ${VERSION}"

# ── 4. Verificar se já está instalado ────────────────────────────────────────
if [[ -d "${INSTALL_DIR}/${APP_NAME}.app" ]]; then
    INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
        "${INSTALL_DIR}/${APP_NAME}.app/Contents/Info.plist" 2>/dev/null || echo "desconhecida")

    # Remover 'v' do version tag para comparação
    CLEAN_VERSION="${VERSION#v}"
    if [[ "$INSTALLED_VERSION" == "$CLEAN_VERSION" ]]; then
        ok "Versão ${VERSION} já está instalada."
        echo ""
        echo "Para reinstalar, remova o app primeiro:"
        echo "  rm -rf '${INSTALL_DIR}/${APP_NAME}.app'"
        echo ""
        exit 0
    fi
    warn "Atualizando de ${INSTALLED_VERSION} → ${CLEAN_VERSION}…"
fi

# ── 5. Download ───────────────────────────────────────────────────────────────
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

log "Baixando ${VERSION}…"
curl -fsSL --progress-bar "$DOWNLOAD_URL" -o "${TMP_DIR}/ClipboardManager.zip"
ok "Download concluído."

# ── 6. Extrair ────────────────────────────────────────────────────────────────
log "Extraindo…"
unzip -q "${TMP_DIR}/ClipboardManager.zip" -d "${TMP_DIR}/extracted"

APP_BUNDLE=$(find "${TMP_DIR}/extracted" -name "*.app" -maxdepth 2 | head -1)
[[ -z "$APP_BUNDLE" ]] && err "Nenhum .app encontrado no arquivo baixado."

# ── 7. Instalar em /Applications ─────────────────────────────────────────────
log "Instalando em ${INSTALL_DIR}…"

if [[ -d "${INSTALL_DIR}/${APP_NAME}.app" ]]; then
    rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
fi

cp -r "$APP_BUNDLE" "${INSTALL_DIR}/${APP_NAME}.app"
ok "App instalado."

# ── 8. Remover quarentena (Gatekeeper) ────────────────────────────────────────
# Necessário pois o app não é notarizado pela Apple
log "Removendo atributo de quarentena…"
xattr -dr com.apple.quarantine "${INSTALL_DIR}/${APP_NAME}.app" 2>/dev/null && \
    ok "Quarentena removida." || \
    warn "Não foi possível remover quarentena (pode ser necessário permissão)."

# ── 9. Abrir o app ────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✓ Clipboard Manager instalado com sucesso!${RESET}"
echo ""
echo "  • Atalho global: ⌥V (Option + V)"
echo "  • Na primeira execução, conceda permissão de Acessibilidade"
echo "    em: Ajustes do Sistema → Privacidade → Acessibilidade"
echo ""

read -r -p "  Deseja abrir o Clipboard Manager agora? [S/n] " REPLY
REPLY="${REPLY:-S}"
if [[ "$REPLY" =~ ^[Ss]$ ]]; then
    open "${INSTALL_DIR}/${APP_NAME}.app"
    ok "Iniciando…"
fi

echo ""
