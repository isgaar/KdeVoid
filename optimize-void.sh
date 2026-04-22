#!/bin/bash
# ============================================================
#  Optimizador de rendimiento para Void Linux
#  KDE Plasma — Ryzen + NVMe + 16GB RAM
# ============================================================
#  Repositorio: https://github.com/isgaar/KdeVoid
# ============================================================

set -euo pipefail

# ─────────────────────────── Colores ─────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─────────────────────────── Tema verde oscuro ────────────────────────────
export NEWT_COLORS='
root=,black
border=green,black
title=green,black
roottext=white,black
window=,black
textbox=white,black
button=black,green
actbutton=white,darkgreen
checkbox=white,black
actcheckbox=black,green
entry=white,black
label=green,black
listbox=white,black
actlistbox=black,green
sellistbox=black,darkgreen
actsellistbox=black,green
compactbutton=white,black
emptyscale=,black
fullscale=,green
listheader=black,green
acthdr=black,green
'

TITLE="Optimizador de Rendimiento — Void Linux"
BACKTITLE="KDE Plasma para Void Linux | github.com/isgaar/KdeVoid"

TERM_HEIGHT=$(tput lines 2>/dev/null || echo 24)
TERM_WIDTH=$(tput cols  2>/dev/null || echo 80)
HEIGHT=$TERM_HEIGHT
WIDTH=$TERM_WIDTH
MENU_HEIGHT=$(( HEIGHT - 10 ))

LOGFILE_DIR="$HOME/.local/state/kde-void-installer"
LOGFILE="$LOGFILE_DIR/optimize.log"
mkdir -p "$LOGFILE_DIR"

# ─────────────────────────── Helpers ─────────────────────────────────────
log() {
    echo -e "$*"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOGFILE"
}

msgbox() {
    whiptail --title "$TITLE" --backtitle "$BACKTITLE" --msgbox "$1" $HEIGHT $WIDTH
}

yesno() {
    whiptail --title "$TITLE" --backtitle "$BACKTITLE" --yesno "$1" 12 65
}

enable_service() {
    local svc="$1"
    if [ -d "/etc/sv/$svc" ]; then
        if [ ! -e "/var/service/$svc" ]; then
            sudo ln -sf "/etc/sv/$svc" /var/service/
            log "  -> Servicio habilitado: $svc"
        else
            log "  -> Servicio ya activo: $svc"
        fi
    else
        log "  -> Advertencia: servicio '$svc' no encontrado en /etc/sv/"
    fi
}

check_root() {
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}No ejecutes este script como root. Se pedira sudo cuando sea necesario.${RESET}"
        exit 1
    fi
}

# ─────────────────────────── Deteccion de hardware ───────────────────────
detect_disk() {
    local ROOT_DEV DISK_TYPE IO_SCHED

    ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null \
        | sed 's/p\?[0-9]\+$//' \
        | xargs -I{} basename {} 2>/dev/null \
        || echo "sda")
    ROOT_DEV=$(basename "$ROOT_DEV" 2>/dev/null || echo "sda")

    if [[ "$ROOT_DEV" == nvme* ]]; then
        DISK_TYPE="nvme"
        IO_SCHED="none"
    elif [ -f "/sys/block/${ROOT_DEV}/queue/rotational" ] && \
         [ "$(cat /sys/block/${ROOT_DEV}/queue/rotational 2>/dev/null)" = "0" ]; then
        DISK_TYPE="ssd"
        IO_SCHED="mq-deadline"
    else
        DISK_TYPE="hdd"
        IO_SCHED="bfq"
    fi

    echo "$ROOT_DEV $DISK_TYPE $IO_SCHED"
}

# ─────────────────────────── Modulos ─────────────────────────────────────

do_zram() {
    log "─── [1/8] zram — swap comprimida en RAM ───"

    sudo xbps-install -Suy zramen 2>/dev/null || \
    sudo xbps-install -Suy zram-generator 2>/dev/null || true

    local TOTAL_RAM_MB
    TOTAL_RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "4096")

    # Tamaño adaptativo: 50% RAM, mínimo 512MB, máximo 4096MB
    local ZRAM_SIZE_MB=$(( TOTAL_RAM_MB / 2 ))
    [ "$ZRAM_SIZE_MB" -lt 512 ]  && ZRAM_SIZE_MB=512
    [ "$ZRAM_SIZE_MB" -gt 4096 ] && ZRAM_SIZE_MB=4096

    # Swappiness adaptativo: menos agresivo con más RAM (como macOS)
    local SWAPPINESS=10
    [ "$TOTAL_RAM_MB" -lt 8192 ] && SWAPPINESS=20
    [ "$TOTAL_RAM_MB" -lt 4096 ] && SWAPPINESS=35

    # Configurar módulo al arranque
    sudo mkdir -p /etc/modprobe.d
    sudo tee /etc/modprobe.d/zram.conf > /dev/null << EOF
options zram num_devices=1
EOF

    sudo mkdir -p /etc/udev/rules.d
    sudo tee /etc/udev/rules.d/99-zram.rules > /dev/null << EOF
KERNEL=="zram0", ATTR{disksize}="${ZRAM_SIZE_MB}M", ATTR{comp_algorithm}="lz4", RUN+="/sbin/mkswap /dev/zram0", RUN+="/sbin/swapon -p 100 /dev/zram0"
EOF

    # Activar ahora mismo sin reiniciar
    sudo modprobe zram num_devices=1 2>/dev/null || true
    if [ -b /dev/zram0 ]; then
        # Desactivar primero si ya estaba montado
        sudo swapoff /dev/zram0 2>/dev/null || true
        echo 1 | sudo tee /sys/block/zram0/reset > /dev/null 2>&1 || true
        echo lz4 | sudo tee /sys/block/zram0/comp_algorithm > /dev/null 2>&1 || true
        echo "${ZRAM_SIZE_MB}M" | sudo tee /sys/block/zram0/disksize > /dev/null 2>&1 && \
        sudo mkswap /dev/zram0 > /dev/null 2>&1 && \
        sudo swapon -p 100 /dev/zram0 > /dev/null 2>&1 && \
        log "  -> zram0 activo ahora (${ZRAM_SIZE_MB}MB, lz4)" || \
        log "  -> zram0 se activara tras reiniciar"
    fi

    # Aplicar sysctl de memoria ahora mismo
    sudo mkdir -p /etc/sysctl.d
    sudo tee /etc/sysctl.d/99-zram-memory.conf > /dev/null << EOF
vm.swappiness            = ${SWAPPINESS}
vm.page-cluster          = 0
vm.vfs_cache_pressure    = 50
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
EOF
    sudo sysctl -p /etc/sysctl.d/99-zram-memory.conf > /dev/null 2>&1 || true

    log "  -> zram: ${ZRAM_SIZE_MB}MB lz4 | swappiness=${SWAPPINESS} | RAM=${TOTAL_RAM_MB}MB"
    echo "$ZRAM_SIZE_MB"
}

do_earlyoom() {
    log "─── [2/8] earlyoom — proteccion OOM ───"
    sudo xbps-install -Suy earlyoom 2>/dev/null || true
    enable_service earlyoom

    if [ -f /etc/earlyoom ]; then
        sudo tee /etc/earlyoom > /dev/null << 'EOF'
EARLYOOM_ARGS="-r 60 -m 5 -s 10 --prefer '(^|/)(chrome|firefox|Web Content)$' --avoid '(^|/)(sddm|plasmashell|kwin)$'"
EOF
    fi
    log "  -> earlyoom: mata procesos si RAM < 5%, protege plasmashell/kwin"
}

do_ananicy() {
    log "─── [3/8] ananicy-cpp — prioridades de CPU ───"
    sudo xbps-install -Suy ananicy-cpp 2>/dev/null || true

    if command -v ananicy-cpp &>/dev/null || [ -f /usr/bin/ananicy ]; then
        enable_service ananicy-cpp 2>/dev/null || \
        enable_service ananicy    2>/dev/null || true
        log "  -> ananicy-cpp habilitado"
    else
        log "  -> ananicy-cpp no disponible en repos (omitido)"
    fi
}

do_irqbalance() {
    log "─── [4/8] irqbalance — distribuir IRQs entre nucleos ───"
    sudo xbps-install -Suy irqbalance 2>/dev/null || true
    enable_service irqbalance
    log "  -> irqbalance habilitado"
}

do_sysctl() {
    log "─── [5/8] sysctl — parametros kernel para desktop AMD/NVMe ───"
    sudo mkdir -p /etc/sysctl.d
    sudo tee /etc/sysctl.d/99-desktop-performance.conf > /dev/null << 'EOF'
# ── Optimizacion KDE Void Linux — Ryzen + NVMe + 16GB ──────────────────

# RAM / swap
vm.swappiness                  = 10
vm.vfs_cache_pressure          = 50
vm.dirty_ratio                 = 10
vm.dirty_background_ratio      = 5
vm.dirty_expire_centisecs      = 3000
vm.dirty_writeback_centisecs   = 500

# NVMe — no leer paginas extra en swap
vm.page-cluster                = 0

# Red — mejor throughput para Flatpak y descargas
net.core.rmem_max              = 134217728
net.core.wmem_max              = 134217728
net.core.netdev_max_backlog    = 5000
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen          = 3
net.core.default_qdisc         = fq

# CPU / scheduler
kernel.sched_autogroup_enabled = 1
kernel.nmi_watchdog            = 0

# Flatpak / bubblewrap
kernel.unprivileged_userns_clone = 1
EOF

    sudo sysctl -p /etc/sysctl.d/99-desktop-performance.conf > /dev/null 2>&1 || true
    log "  -> sysctl aplicado"
}

do_io_scheduler() {
    local ROOT_DEV="$1"
    local DISK_TYPE="$2"
    local IO_SCHED="$3"

    log "─── [6/8] I/O scheduler — $IO_SCHED para $ROOT_DEV ($DISK_TYPE) ───"

    sudo mkdir -p /etc/udev/rules.d
    sudo tee /etc/udev/rules.d/60-io-scheduler.rules > /dev/null << 'EOF'
# I/O scheduler optimo segun tipo de disco
# NVMe → none | SSD SATA → mq-deadline | HDD → bfq
ACTION=="add|change", KERNEL=="nvme[0-9]*",   ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF

    if [ -f "/sys/block/${ROOT_DEV}/queue/scheduler" ]; then
        echo "$IO_SCHED" | sudo tee "/sys/block/${ROOT_DEV}/queue/scheduler" > /dev/null 2>&1 || true
        log "  -> I/O scheduler '$IO_SCHED' aplicado a /dev/$ROOT_DEV"
    fi
}

do_cpu_governor() {
    log "─── [7/8] CPU governor — schedutil (optimo para Ryzen boost) ───"

    sudo mkdir -p /etc/udev/rules.d
    sudo tee /etc/udev/rules.d/50-cpu-governor.rules > /dev/null << 'EOF'
# schedutil: governor reactivo via scheduler del kernel
# Ideal para Ryzen con Precision Boost automatico
ACTION=="add", SUBSYSTEM=="cpu", ATTR{cpufreq/scaling_governor}="schedutil"
EOF

    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$gov" ] && echo "schedutil" | sudo tee "$gov" > /dev/null 2>&1 || true
    done

    local CORES
    CORES=$(nproc 2>/dev/null || echo "?")
    log "  -> schedutil aplicado a $CORES nucleos"
}

do_flathub_mirror() {
    log "─── [8/8] Flathub CDN — mirror mas rapido para Mexico ───"

    if ! command -v flatpak &>/dev/null; then
        log "  -> Flatpak no instalado, omitiendo mirror"
        return 0
    fi

    sudo flatpak remote-modify flathub \
        --url=https://dl.flathub.org/repo/ 2>/dev/null || true
    flatpak remote-modify --user flathub \
        --url=https://dl.flathub.org/repo/ 2>/dev/null || true

    if [ -f /var/lib/flatpak/repo/config ]; then
        sudo git config --file /var/lib/flatpak/repo/config \
            core.min-free-space-percent 5 2>/dev/null || true
    fi

    log "  -> Flathub apuntando a CDN Fastly (dl.flathub.org)"
}

do_preload() {
    log "─── [extra] preload — precarga apps frecuentes en RAM ───"
    sudo xbps-install -Suy preload 2>/dev/null || true
    enable_service preload 2>/dev/null || true
    log "  -> preload instalado y habilitado"
}

# ─────────────────────────── Menu principal ──────────────────────────────

main() {
    check_root

    whiptail --title "$TITLE" --backtitle "$BACKTITLE" --msgbox \
"Bienvenido al Optimizador de Void Linux.

Este script mejora el rendimiento del sistema para:
  CPU:   AMD Ryzen (schedutil + ananicy-cpp + irqbalance)
  RAM:   zram swap comprimida con lz4 + earlyoom
  Disco: I/O scheduler optimo (NVMe/SSD/HDD auto-detectado)
  Red:   TCP BBR + Flathub CDN Mexico (Flatpak mas rapido)
  KDE:   sysctl tunado para desktop responsivo

Repositorio: https://github.com/isgaar/KdeVoid

Presiona ENTER para continuar." \
    22 64

    # Detectar hardware
    read -r ROOT_DEV DISK_TYPE IO_SCHED <<< "$(detect_disk)"
    log "Hardware detectado: disco=$ROOT_DEV tipo=$DISK_TYPE scheduler=$IO_SCHED"

    # Checklist — el usuario elige que modulos aplicar
    local RAW
    RAW=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
        --checklist "Selecciona las optimizaciones a aplicar:\n(Barra espaciadora para marcar/desmarcar)" \
        $HEIGHT $WIDTH $MENU_HEIGHT \
        "zram"        "Swap comprimida en RAM con lz4 (50% RAM)"           ON  \
        "earlyoom"    "Proteccion OOM — evita freezes por falta de RAM"    ON  \
        "ananicy"     "Prioridades de CPU por proceso (como QoS de macOS)" ON  \
        "irqbalance"  "Distribuir IRQs entre todos los nucleos CPU"        ON  \
        "sysctl"      "Parametros kernel: vm, net, cpu (TCP BBR incluido)" ON  \
        "io_sched"    "I/O scheduler optimo: $IO_SCHED para $ROOT_DEV ($DISK_TYPE)" ON  \
        "cpu_gov"     "CPU governor schedutil (Ryzen Precision Boost)"     ON  \
        "flathub"     "Mirror Flathub CDN Mexico (Flatpak mas rapido)"     ON  \
        "preload"     "Preload: precarga apps frecuentes en RAM (16GB)"    OFF \
        3>&1 1>&2 2>&3) || { log "Cancelado por el usuario."; exit 0; }

    RAW=${RAW//\"/}
    read -r -a SELECTED <<< "$RAW"

    if [ ${#SELECTED[@]} -eq 0 ]; then
        msgbox "No se selecciono ninguna optimizacion."
        exit 0
    fi

    clear
    log "========== Iniciando optimizacion =========="

    local ZRAM_SIZE_MB=0

    for mod in "${SELECTED[@]}"; do
        case "$mod" in
            zram)       ZRAM_SIZE_MB=$(do_zram) ;;
            earlyoom)   do_earlyoom ;;
            ananicy)    do_ananicy ;;
            irqbalance) do_irqbalance ;;
            sysctl)     do_sysctl ;;
            io_sched)   do_io_scheduler "$ROOT_DEV" "$DISK_TYPE" "$IO_SCHED" ;;
            cpu_gov)    do_cpu_governor ;;
            flathub)    do_flathub_mirror ;;
            preload)    do_preload ;;
        esac
    done

    log "========== Optimizacion completada =========="

    # Resumen
    local SUMMARY="Optimizacion aplicada correctamente.\n\nModulos ejecutados:\n"
    for mod in "${SELECTED[@]}"; do
        SUMMARY+="  [OK] $mod\n"
    done
    SUMMARY+="\nDisco: /dev/$ROOT_DEV ($DISK_TYPE) — scheduler: $IO_SCHED"
    [ "$ZRAM_SIZE_MB" -gt 0 ] 2>/dev/null && \
        SUMMARY+="\nzram:  ${ZRAM_SIZE_MB}MB swap comprimida (lz4)"
    SUMMARY+="\n\nLog guardado en:\n  $LOGFILE"
    SUMMARY+="\n\nReinicia para aplicar zram y udev completamente.\n\nVerifica con:\n  cat /proc/swaps\n  cat /sys/block/*/queue/scheduler\n  cpupower frequency-info"

    msgbox "$SUMMARY"

    if whiptail --title "$TITLE" --backtitle "$BACKTITLE" --yesno \
        "Reiniciar ahora para aplicar todos los cambios?" 8 50; then
        sudo reboot
    fi
}

main
