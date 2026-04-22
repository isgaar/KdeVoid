#!/usr/bin/env bash
# apply_complete_config.sh — Configuración de fuentes
# Autores: Ismael & Gemini AI
# Optimizado para: Void Linux / Arch Linux (KDE/Wayland)

set -euo pipefail

# Colores para la terminal del script
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FONTCONFIG_DIR="$HOME/.config/fontconfig"
FONTS_CONF="$FONTCONFIG_DIR/fonts.conf"
ENV_FILE="/etc/environment"
STEM_LINE='FREETYPE_PROPERTIES="cff:no-stem-darkening=0 autofitter:no-stem-darkening=0"'

echo -e "${BLUE}=== Iniciando Configuración Maestra para Ismael ===${NC}\n"

# --- 1. CONFIGURACIÓN DE FUENTES (fontconfig) ---
echo -e "${BLUE}→${NC} Configurando fuentes en $FONTCONFIG_DIR..."
mkdir -p "$FONTCONFIG_DIR"

cat > "$FONTS_CONF" << 'XMLEOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
    <edit name="rgba" mode="assign"><const>none</const></edit>
    <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
    <edit name="embeddedbitmap" mode="assign"><bool>false</bool></edit>
  </match>
  <selectfont>
    <acceptfont>
      <pattern><patelt name="scalable"><bool>true</bool></patelt></pattern>
    </acceptfont>
  </selectfont>
</fontconfig>
XMLEOF

# --- 2. FREETYPE (Stem Darkening en /etc/environment) ---
echo -e "${BLUE}→${NC} Verificando stem-darkening..."
if grep -q "no-stem-darkening" "$ENV_FILE" 2>/dev/null; then
    echo -e "${YELLOW}i${NC} Freetype ya está configurado en $ENV_FILE."
else
    echo -e "${YELLOW}!${NC} Se requieren permisos de root para $ENV_FILE"
    echo "$STEM_LINE" | sudo tee -a "$ENV_FILE" > /dev/null
fi

# --- 3. FINALIZAR ---
echo -e "${BLUE}→${NC} Actualizando caché de fuentes..."
fc-cache -fv > /dev/null

echo -e "\n${GREEN}✔ ¡Todo listo, Ismael!${NC}"
echo -e "--------------------------------------------------"
echo -e "1. Fuentes optimizadas en: ${BLUE}$FONTS_CONF${NC}"
echo -e "--------------------------------------------------"
echo -e "${YELLOW}RECUERDA:${NC} Reinicia sesión para aplicar el renderizado de fuentes en todo el sistema."
