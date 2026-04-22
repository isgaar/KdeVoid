#!/bin/bash
# setup-zram.sh — Configura zram swap (activa ahora + persiste al arranque)
# Void Linux / AMD Ryzen

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}No ejecutes como root. Se pedira sudo cuando sea necesario.${RESET}"
    exit 1
fi

# ── Detectar RAM y calcular tamaño ────────────────────────────────────────
TOTAL_RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
ZRAM_SIZE_MB=$(( TOTAL_RAM_MB / 2 ))
[ "$ZRAM_SIZE_MB" -gt 4096 ] && ZRAM_SIZE_MB=4096
[ "$ZRAM_SIZE_MB" -lt 512  ] && ZRAM_SIZE_MB=512

SWAPPINESS=10
[ "$TOTAL_RAM_MB" -lt 8192 ] && SWAPPINESS=20
[ "$TOTAL_RAM_MB" -lt 4096 ] && SWAPPINESS=35

echo -e "${CYAN}=== Configurando zram swap ===${RESET}"
echo -e "  RAM detectada:  ${TOTAL_RAM_MB}MB"
echo -e "  zram tamanio:   ${ZRAM_SIZE_MB}MB (lz4)"
echo -e "  swappiness:     ${SWAPPINESS}\n"

# ── Verificar si ya hay swap activa ───────────────────────────────────────
if swapon --show 2>/dev/null | grep -q "^/dev/zram"; then
    echo -e "${YELLOW}zram ya esta activo:${RESET}"
    swapon --show
    exit 0
fi

# ── 1. Limpiar estado anterior del módulo ────────────────────────────────
echo -e "${CYAN}→${RESET} Limpiando estado anterior de zram..."
sudo swapoff /dev/zram0 2>/dev/null || true
sudo rmmod zram 2>/dev/null || true
sleep 1

# ── 2. Carga limpia del módulo ────────────────────────────────────────────
echo -e "${CYAN}→${RESET} Cargando modulo zram..."
sudo modprobe zram num_devices=1 || {
    echo -e "${RED}Error: no se pudo cargar el modulo zram.${RESET}"
    exit 1
}
sleep 1

if [ ! -b /dev/zram0 ]; then
    echo -e "${RED}Error: /dev/zram0 no aparecio tras modprobe.${RESET}"
    exit 1
fi

# ── 3. Configurar y activar zram0 ────────────────────────────────────────
echo -e "${CYAN}→${RESET} Configurando zram0..."
echo lz4 | sudo tee /sys/block/zram0/comp_algorithm > /dev/null
echo "${ZRAM_SIZE_MB}M" | sudo tee /sys/block/zram0/disksize > /dev/null
sudo mkswap /dev/zram0
sudo swapon -p 100 /dev/zram0

# ── 4. Persistencia al arranque ───────────────────────────────────────────
echo -e "${CYAN}→${RESET} Configurando persistencia..."

sudo mkdir -p /etc/modules-load.d
echo "zram" | sudo tee /etc/modules-load.d/zram.conf > /dev/null

sudo mkdir -p /etc/modprobe.d
sudo tee /etc/modprobe.d/zram.conf > /dev/null << 'EOF'
options zram num_devices=1
EOF

sudo mkdir -p /etc/udev/rules.d
sudo tee /etc/udev/rules.d/99-zram.rules > /dev/null << EOF
KERNEL=="zram0", ATTR{disksize}="${ZRAM_SIZE_MB}M", ATTR{comp_algorithm}="lz4", RUN+="/sbin/mkswap /dev/zram0", RUN+="/sbin/swapon -p 100 /dev/zram0"
EOF

# ── 5. sysctl ─────────────────────────────────────────────────────────────
echo -e "${CYAN}→${RESET} Aplicando sysctl de memoria..."
sudo mkdir -p /etc/sysctl.d
sudo tee /etc/sysctl.d/99-zram-memory.conf > /dev/null << EOF
vm.swappiness             = ${SWAPPINESS}
vm.page-cluster           = 0
vm.vfs_cache_pressure     = 50
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
EOF
sudo sysctl -p /etc/sysctl.d/99-zram-memory.conf > /dev/null 2>&1

# ── Resumen ───────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}✔ zram swap activo${RESET}"
echo -e "──────────────────────────────────────"
free -h | grep -E "Mem|Swap"
echo ""
cat /proc/swaps
echo -e "──────────────────────────────────────"
echo -e "  Algoritmo:  lz4"
echo -e "  Prioridad:  100 (preferida sobre swap en disco)"
echo -e "  swappiness: ${SWAPPINESS}"
echo -e "──────────────────────────────────────"
echo -e "${YELLOW}Persistente:${RESET} modules-load.d + udev lo activaran en cada arranque."