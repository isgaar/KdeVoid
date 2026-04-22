#!/bin/bash
# setup-zram.sh — Configura zram swap ahora mismo
# Para: Void Linux / AMD Ryzen / 6.78GB RAM

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

echo -e "${CYAN}=== Configurando zram swap ===${RESET}\n"

# ── Detectar RAM ──────────────────────────────────────────────────────────
TOTAL_RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
ZRAM_SIZE_MB=$(( TOTAL_RAM_MB / 2 ))
[ "$ZRAM_SIZE_MB" -gt 4096 ] && ZRAM_SIZE_MB=4096
[ "$ZRAM_SIZE_MB" -lt 512  ] && ZRAM_SIZE_MB=512

# Swappiness adaptativo
SWAPPINESS=10
[ "$TOTAL_RAM_MB" -lt 8192 ] && SWAPPINESS=20
[ "$TOTAL_RAM_MB" -lt 4096 ] && SWAPPINESS=35

echo -e "  RAM detectada:  ${TOTAL_RAM_MB}MB"
echo -e "  zram tamanio:   ${ZRAM_SIZE_MB}MB (lz4)"
echo -e "  swappiness:     ${SWAPPINESS}"
echo ""

# ── Verificar si ya hay swap ──────────────────────────────────────────────
if swapon --show 2>/dev/null | grep -q "^/"; then
    echo -e "${YELLOW}Ya existe swap activa:${RESET}"
    swapon --show
    exit 0
fi

# ── Cargar módulo zram ────────────────────────────────────────────────────
echo -e "${CYAN}→${RESET} Cargando modulo zram..."
sudo modprobe zram num_devices=1 2>/dev/null || {
    echo -e "${RED}Error: no se pudo cargar el modulo zram.${RESET}"
    echo "Verifica con: modinfo zram"
    exit 1
}

# ── Activar zram0 ─────────────────────────────────────────────────────────
echo -e "${CYAN}→${RESET} Configurando zram0..."
sudo swapoff /dev/zram0 2>/dev/null || true
echo 1 | sudo tee /sys/block/zram0/reset          > /dev/null 2>&1 || true
echo lz4 | sudo tee /sys/block/zram0/comp_algorithm > /dev/null
echo "${ZRAM_SIZE_MB}M" | sudo tee /sys/block/zram0/disksize > /dev/null
sudo mkswap /dev/zram0
sudo swapon -p 100 /dev/zram0

echo -e "${GREEN}✔ zram0 activo${RESET}"

# ── Persistencia al arranque ──────────────────────────────────────────────
echo -e "${CYAN}→${RESET} Configurando persistencia..."

sudo mkdir -p /etc/modprobe.d
sudo tee /etc/modprobe.d/zram.conf > /dev/null << EOF
options zram num_devices=1
EOF

sudo mkdir -p /etc/udev/rules.d
sudo tee /etc/udev/rules.d/99-zram.rules > /dev/null << EOF
KERNEL=="zram0", ATTR{disksize}="${ZRAM_SIZE_MB}M", ATTR{comp_algorithm}="lz4", RUN+="/sbin/mkswap /dev/zram0", RUN+="/sbin/swapon -p 100 /dev/zram0"
EOF

# ── sysctl ────────────────────────────────────────────────────────────────
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
echo -e "${GREEN}=== Todo listo ===${RESET}"
echo -e "--------------------------------------------------"
free -h | grep -E "Mem|Swap"
echo ""
cat /proc/swaps
echo -e "--------------------------------------------------"
echo -e "  Algoritmo:  lz4"
echo -e "  Prioridad:  100 (preferida sobre swap en disco)"
echo -e "  swappiness: ${SWAPPINESS}"
echo -e "--------------------------------------------------"
echo -e "${YELLOW}Persistente:${RESET} se activara automaticamente en cada arranque."
