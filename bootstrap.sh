#!/bin/bash
# ============================================================
#  Bootstrap — KDE Plasma Installer para Void Linux
#  Descarga e inicia el instalador automáticamente
# ============================================================
#
#  USO (una sola línea):
#  bash <(curl -sL https://raw.githubusercontent.com/TU_USUARIO/kde-void-installer/main/bootstrap.sh)
#
# ============================================================

set -euo pipefail

REPO_URL="https://github.com/TU_USUARIO/kde-void-installer"
RAW_URL="https://raw.githubusercontent.com/TU_USUARIO/kde-void-installer/main"
INSTALL_DIR="$HOME/kde-void-installer"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║   KDE Plasma Installer — Void Linux          ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
echo ""

# ── Verificar que estamos en Void Linux ──────────────────────────────────
if [ ! -f /etc/void-release ]; then
    echo -e "${YELLOW}Advertencia: Este script está hecho para Void Linux.${RESET}"
fi

# ── Instalar dependencias del instalador ─────────────────────────────────
echo -e "${GREEN}→ Instalando dependencias del instalador (git, newt)...${RESET}"
if ! command -v whiptail &>/dev/null; then
    sudo xbps-install -Sy newt
fi
if ! command -v git &>/dev/null; then
    sudo xbps-install -Sy git
fi

# ── Clonar repositorio ───────────────────────────────────────────────────
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${GREEN}→ Actualizando repositorio existente...${RESET}"
    git -C "$INSTALL_DIR" pull
else
    echo -e "${GREEN}→ Clonando repositorio...${RESET}"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# ── Dar permisos y ejecutar ──────────────────────────────────────────────
chmod +x "$INSTALL_DIR/install-kde.sh"
echo ""
echo -e "${GREEN}✓ Listo. Iniciando instalador...${RESET}"
echo ""
exec "$INSTALL_DIR/install-kde.sh"
