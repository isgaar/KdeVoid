#!/usr/bin/env bash
# import_kde.sh — Aplica la configuración guardada en kde_backup a este sistema

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SOURCE_DIR="$(dirname "$(readlink -f "$0")")/kde_backup"
CONFIG_DIR="$HOME/.config"

if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${RED}✘ Error: No se encontró la carpeta $SOURCE_DIR${NC}"
    exit 1
fi

echo -e "${BLUE}→${NC} Importando configuración de KDE desde $SOURCE_DIR..."

# Archivos a restaurar
FILES=("kdeglobals" "plasmarc" "kwinrc" "kglobalshortcutsrc")

for file in "${FILES[@]}"; do
    if [ -f "$SOURCE_DIR/$file" ]; then
        cp "$SOURCE_DIR/$file" "$CONFIG_DIR/"
        echo -e "  [${GREEN}APLICADO${NC}] $file"
    else
        echo -e "  [${YELLOW}SKIP${NC}] No se encontró $file en el backup"
    fi
done

echo -e "\n${BLUE}→${NC} Recargando configuración de Plasma (sin cerrar sesión)..."

# Comandos mágicos para que KDE lea los archivos nuevos de inmediato
qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || qdbus org.kde.KWin /KWin reconfigure
qdbus6 org.kde.plasmashell /PlasmaShell evaluateScript "var allDesktops = desktops(); for (var i=0; i<allDesktops.length; i++) { allDesktops[i].reloadConfig(); }" 2>/dev/null || echo -e "${YELLOW}!${NC} Nota: Algunos cambios del panel requieren reiniciar sesión."

echo -e "\n${GREEN}✔ ¡Configuración importada con éxito!${NC}"
