#!/bin/bash
# ============================================================
#  KDE Plasma Installer for Void Linux
#  Instalador interactivo de KDE Plasma para Void Linux
# ============================================================
#  Basado en LBAC (Linux Bulk App Chooser)
#  https://codeberg.org/squidnose-code/Linux-Bulk-App-Chooser
# ============================================================

set -euo pipefail

# ─────────────────────────── Colores ─────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─────────────────────────── Interrupción segura ─────────────────────────
_cleanup() {
    local sig="${1:-INT}"
    # Desactivar trap para evitar llamadas recursivas
    trap '' INT QUIT TERM

    # Matar todo el grupo de procesos (sudo, xbps, whiptail, subshells)
    kill -- -$$ 2>/dev/null || true

    # Cerrar FD del gauge si esta abierto
    exec 9>&- 2>/dev/null || true

    # Restaurar terminal
    tput cnorm 2>/dev/null || true
    tput rmcup 2>/dev/null || true
    stty sane 2>/dev/null || true
    clear

    echo -e "\n${YELLOW}[!] Instalacion interrumpida por el usuario (Ctrl+C).${RESET}"
    echo -e "${CYAN}    Los paquetes ya instalados permanecen en el sistema.${RESET}"
    echo -e "${CYAN}    Revisa el log en: ${LOGFILE:-~/.local/state/kde-void-installer/install.log}${RESET}"

    if [ "${LOGGING:-1}" -eq 1 ] && [ -n "${LOGFILE:-}" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [CANCELADO] El usuario interrumpio la instalacion (señal $sig)." \
            >> "$LOGFILE" 2>/dev/null || true
    fi

    exit 130
}

# Iniciar el script en su propio grupo de procesos para poder matarlos todos
set -m 2>/dev/null || true

trap '_cleanup INT'  INT
trap '_cleanup QUIT' QUIT
trap '_cleanup TERM' TERM

# ─────────────────────────── Configuración ───────────────────────────────
TITLE="KDE Plasma Installer — Void Linux"
BACKTITLE="KDE Plasma para Void Linux | github.com/isgaar/KdeVoid"

# ─────────────────────────── Tema whiptail (verde oscuro) ────────────────
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
LOGFILE_DIR="$HOME/.local/state/kde-void-installer"
LOGFILE="$LOGFILE_DIR/install.log"
LOGGING=1

# Variables de hardware (se detectan / eligen en step_hardware)
CPU_VENDOR=""        # "amd" | "intel" | "other"
GPU_VENDOR=""        # "amd" | "nvidia" | "intel" | "other"
IS_LAPTOP=0          # 1 si parece laptop

# ─────────────────────────── Opciones CLI ────────────────────────────────
while getopts "dh" opt; do
    case "$opt" in
        d) LOGGING=0 ;;
        h)
            echo "Uso: $0 [-d] [-h]"
            echo "  -d  Deshabilitar registro (log)"
            echo "  -h  Mostrar esta ayuda"
            exit 0
            ;;
        *) echo "Opcion invalida: -$OPTARG" >&2; exit 1 ;;
    esac
done

# ─────────────────────────── Logging ─────────────────────────────────────
if [ "$LOGGING" -eq 1 ]; then
    mkdir -p "$LOGFILE_DIR"
fi

log() {
    local msg="$*"
    # En modo express el gauge ocupa stdout; solo escribir al archivo
    if [ "${_EXPRESS_MODE:-0}" -eq 0 ]; then
        echo -e "$msg"
    fi
    if [ "$LOGGING" -eq 1 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$LOGFILE"
    fi
}

# ─────────────────────────── Verificaciones previas ──────────────────────
check_dependencies() {
    # xbps-install es obligatorio (estamos en Void Linux)
    if ! command -v xbps-install &>/dev/null; then
        echo -e "${RED}Error: xbps-install no encontrado. Este script requiere Void Linux.${RESET}"
        exit 1
    fi

    # Instalar whiptail automaticamente si no esta presente
    if ! command -v whiptail &>/dev/null; then
        echo -e "${YELLOW}whiptail no encontrado. Instalando newt...${RESET}"
        if ! sudo xbps-install -Suy newt; then
            echo -e "${RED}Error: No se pudo instalar newt (whiptail).${RESET}"
            echo "Instala manualmente con: sudo xbps-install -Suy newt"
            exit 1
        fi
        if ! command -v whiptail &>/dev/null; then
            echo -e "${RED}Error: whiptail sigue sin encontrarse tras instalar newt.${RESET}"
            exit 1
        fi
        echo -e "${GREEN}whiptail instalado correctamente.${RESET}"
    fi
}

check_void_linux() {
    if [ ! -f /etc/void-release ]; then
        whiptail --title "Advertencia" --yesno \
            "Este script esta disenado para Void Linux.\nParece que estas usando otro sistema.\n\nDeseas continuar de todos modos?" \
            10 60 || exit 0
    fi
}

check_root() {
    if [ "$EUID" -eq 0 ]; then
        whiptail --title "Advertencia" --msgbox \
            "No ejecutes este script como root.\nSe pedira sudo cuando sea necesario." \
            8 55
        exit 1
    fi
}

# ─────────────────────────── Tamaño de terminal ──────────────────────────
TERM_HEIGHT=$(tput lines 2>/dev/null || echo 24)
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
HEIGHT=$(( TERM_HEIGHT ))
WIDTH=$(( TERM_WIDTH ))
MENU_HEIGHT=$(( HEIGHT - 10 ))

# ─────────────────────────── Grupos de paquetes ──────────────────────────

BASE_PACKAGES=(
    xorg
    xorg-server
    xorg-input-drivers
    xorg-video-drivers
    xinit
    xinput
    xrandr
    xset
    xsetroot
    xdpyinfo
    wayland
    dbus
    NetworkManager
)

PLASMA_CORE_OPTS=(
    "kde5"                         "Meta paquete KDE Plasma (kde5 o kde-plasma segun repo)" ON
    "kde-baseapps"                 "Kate, Konsole, Khelpcenter" ON
    "plasma-integration"           "Plugins de integracion de tema para Plasma" ON
    "plasma-browser-integration"   "Integracion del navegador con Plasma 6" OFF
    "plasma-wayland-protocols"     "Protocolos Wayland especificos de Plasma" ON
    "xdg-desktop-portal-kde"       "Backend xdg-desktop-portal para Qt/KF6" ON
    "kwalletmanager"               "Administrador del monedero KDE" OFF
    "breeze"                       "Estilo visual Breeze para Plasma" ON
    "sddm"                         "Gestor de inicio de sesion recomendado para KDE" ON
)

PLASMA_APPS_OPTS=(
    "dolphin"                      "Gestor de archivos Dolphin" ON
    "konsole"                      "Emulador de terminal de KDE" ON
    "spectacle"                    "Captura de pantalla de KDE" ON
    "ark"                          "Archivador de KDE (zip, tar, rar...)" ON
    "gwenview"                     "Visor de imagenes de KDE" ON
    "kwrite"                       "Editor de texto simple de KDE" ON
    "kcalc"                        "Calculadora cientifica de KDE" ON
    "kdeconnect"                   "Conecta tu telefono con el escritorio" ON
    "vlc"                          "Reproductor multimedia universal" ON
    "kdegraphics-thumbnailers"     "Miniaturas de graficos en Dolphin" ON
    "ffmpegthumbs"                 "Miniaturas de video en Dolphin" ON
    "okular"                       "Lector de PDF y documentos de KDE" OFF
    "kolourpaint"                  "Editor de imagenes simple para KDE" OFF
    "filelight"                    "Visualizador de uso de disco" OFF
    "krename"                      "Renombrador de archivos en lote para KDE" OFF
    "elisa"                        "Reproductor de musica de KDE" OFF
    "octoxbps"                     "Frontend grafico para XBPS (Void)" OFF
    "discover"                     "Tienda de aplicaciones KDE Discover" ON
    "packagekit-qt5"               "Backend PackageKit para Discover (XBPS)" ON
)

PLASMA_OPTIONAL_OPTS=(
    "kio-gdrive"                   "Acceso a Google Drive desde Dolphin" OFF
    "kio-extras"                   "Componentes KIO adicionales" OFF
    "ufw"                          "Firewall sin complicaciones (UFW)" OFF
    "plasma-firewall"              "Panel de control para UFW en Plasma" OFF
    "flatpak-kcm"                  "Modulo KDE para permisos Flatpak" OFF
    "discover-flatpak-backend"     "Backend Flatpak para Discover (Flathub)" OFF
    "fwupd"                        "Actualizaciones de firmware" OFF
    "discover-fwupd-backend"       "Backend fwupd para Discover (firmware)" OFF
    "clinfo"                       "Informacion OpenCL del sistema" OFF
    "aha"                          "Conversor ANSI a HTML para centro de info" OFF
    "wayland-utils"                "Utilidades Wayland" OFF
    "kdegraphics-thumbnailers"     "Miniaturas de graficos en Dolphin" ON
    "ffmpegthumbs"                 "Miniaturas de video en Dolphin" ON
    "ksystemlog"                   "Visor de logs del sistema" OFF
)

PLASMA_PIM_OPTS=(
    "korganizer"                   "Calendario y planificador KDE" OFF
    "kontact"                      "Gestor de informacion personal KDE" OFF
    "calendarsupport"              "Libreria de soporte de calendario" OFF
    "kdepim-addons"                "Addons para aplicaciones KDE PIM" OFF
    "kdepim-runtime"               "Runtime de KDE PIM" OFF
    "akonadi-calendar"             "Integracion de calendario con Akonadi" OFF
    "akonadi-contacts"             "Gestion de contactos con Akonadi" OFF
    "akonadi-import-wizard"        "Importar correo desde otros clientes" OFF
)

AUDIO_OPTS=(
    "pipewire"                     "Servidor PipeWire + WirePlumber (obligatorio)" ON
    "alsa-pipewire"                "Integracion ALSA con PipeWire (recomendado)" ON
    "alsa-utils"                   "Utilidades ALSA (amixer, aplay...)" ON
    "libspa-bluetooth"             "Soporte Bluetooth para PipeWire" OFF
    "libjack-pipewire"             "Interfaz JACK via PipeWire" OFF
    "pavucontrol-qt"               "Control de volumen grafico (Qt, nativo KDE)" ON
    "pulseaudio-utils"             "pactl para verificar PulseAudio/PipeWire" ON
)

XINPUT_OPTS=(
    "xinput"                       "Configurar dispositivos X (mouse/teclado/touchpad)" ON
    "xorg-input-drivers"           "Meta-paquete drivers de entrada X (evdev, libinput)" ON
    "libinput"                     "Handler de eventos de entrada moderno" ON
    "xf86-input-libinput"          "Driver X11 basado en libinput (recomendado)" ON
    "xf86-input-evdev"             "Driver X11 evdev generico" OFF
    "xf86-input-synaptics"         "Driver legacy Synaptics para touchpads viejos" OFF
    "xf86-input-wacom"             "Driver para tabletas Wacom" OFF
    "xset"                         "Ajusta parametros del servidor X (velocidad de teclado)" ON
    "xrandr"                       "Configuracion de resolucion y pantallas" ON
    "xdpyinfo"                     "Informacion del servidor X (debug)" OFF
    "setxkbmap"                    "Configurar distribucion de teclado en X" ON
)

TLP_OPTS=(
    "tlp"       "Daemon principal de ahorro de energia" ON
    "tlp-rdw"   "Radio Device Wizard: controla WiFi/BT al suspender" ON
    "tlp-pd"    "Soporte power-profiles-daemon para TLP (tlp-pd)" ON
    "tlpui"     "Interfaz grafica GTK para configurar TLP" OFF
    "powertop"  "Monitor de consumo energetico por proceso" OFF
    "acpid"     "Daemon de eventos ACPI (bateria, tapa de laptop)" OFF
    "thermald"  "Daemon de gestion termica (Intel recomendado)" OFF
    "cpupower"  "Herramienta de perfiles de frecuencia de CPU" OFF
)

PYTHON_OPTS=(
    "python3-dbus"                 "Dependencia Python para Eduroam WiFi" OFF
)

# ─────────────────────────── Funciones de menu ───────────────────────────

checklist_menu() {
    local title="$1"
    local desc="$2"
    shift 2
    whiptail --title "$title" --backtitle "$BACKTITLE" \
        --checklist "$desc\n\nBarra espaciadora para seleccionar/deseleccionar:" \
        $HEIGHT $WIDTH $MENU_HEIGHT \
        "$@" \
        3>&1 1>&2 2>&3
}

msgbox() {
    whiptail --title "$TITLE" --backtitle "$BACKTITLE" --msgbox "$1" $HEIGHT $WIDTH
}

yesno() {
    whiptail --title "$TITLE" --backtitle "$BACKTITLE" --yesno "$1" 10 65
}

radiolist_menu() {
    local title="$1"
    local desc="$2"
    shift 2
    whiptail --title "$title" --backtitle "$BACKTITLE" \
        --radiolist "$desc" \
        $HEIGHT $WIDTH $MENU_HEIGHT \
        "$@" \
        3>&1 1>&2 2>&3
}

# ─────────────────────────── Instalacion ─────────────────────────────────

install_packages() {
    local packages=("$@")
    if [ ${#packages[@]} -eq 0 ]; then
        log "  -> Sin paquetes para instalar en este grupo"
        return 0
    fi
    log "  -> Instalando: ${packages[*]}"
    sudo xbps-install -Suy "${packages[@]}"
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

# ─────────────────────────── PASO 0: Bienvenida ──────────────────────────

step_welcome() {
    whiptail --title "$TITLE" --backtitle "$BACKTITLE" --msgbox \
"Bienvenido, $USER.

Este instalador te guiara paso a paso para instalar
KDE Plasma 6 en tu sistema Void Linux.

Repositorio: https://github.com/isgaar/KdeVoid

Podras elegir exactamente que componentes instalar:
  - Microcódigo CPU (AMD/Intel)
  - Drivers de VIDEO (Intel / AMD / NVIDIA)
  - Drivers de entrada (xinput/libinput)
  - Audio (PipeWire)
  - KDE Plasma 6 y aplicaciones
  - KDE Discover (tienda de apps)
  - Gestion de energia (TLP)
  - Timeshift para instantaneas del sistema

Presiona ENTER para continuar." \
    22 64
}

# ─────────────────────────── PASO 1: Actualizar ──────────────────────────

step_update() {
    if yesno "Actualizar el sistema antes de instalar?\n\nSe ejecutara: sudo xbps-install -Suy\n\n(Muy recomendado para evitar conflictos)"; then
        clear
        log "Actualizando sistema..."
        sudo xbps-install -Suy
        msgbox "Sistema actualizado correctamente."
    else
        log "Actualizacion omitida por el usuario."
    fi
}

# ─────────────────────────── PASO 2: Repositorios ────────────────────────

step_repos() {
    # ── Siempre habilitar nonfree y multilib ──────────────────────────────
    clear
    log "Habilitando repositorios privativos (nonfree + multilib)..."
    sudo xbps-install -Suy void-repo-nonfree void-repo-multilib 2>/dev/null || true
    sudo xbps-install -Suy 2>/dev/null || true
    log "  -> void-repo-nonfree habilitado"
    log "  -> void-repo-multilib habilitado"

    # ── Flatpak / Flathub ─────────────────────────────────────────────────
    if yesno "Agregar Flathub (tienda universal de apps)?\n\nRequiere que flatpak este instalado.\nSe instalara flatpak si no esta presente."; then
        sudo xbps-install -Suy flatpak 2>/dev/null || true
        if command -v flatpak &>/dev/null; then
            flatpak remote-add --if-not-exists flathub \
                https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
            log "  -> Flathub agregado"
        fi
    fi

    # ── Drivers de VIDEO (ahora gestionados por step_gpu) ────────────────
    # Los drivers se instalan en el paso dedicado step_gpu (paso a paso)
    # o en install_express via _gp de drivers. No se instalan aqui.

    msgbox "Repositorios configurados:\n\n  [OK]  void-repo-nonfree  (Nvidia, Broadcom, firmwares)\n  [OK]  void-repo-multilib (Steam, Wine, apps 32-bit)\n  $(command -v flatpak &>/dev/null && echo '[OK]' || echo '[ ] ') Flathub\n\nPuedes instalar paquetes privativos normalmente con:\n  sudo xbps-install -Suy <paquete>"
}

# ─────────────────────────── PASO 2b: Configurar entorno shell ───────────

step_shell_env() {
    if ! yesno "Configurar entorno bash (.bashrc / .inputrc)?\n\nEsto aplicara a TODOS los usuarios (skel + existentes):\n  - Prompt estilo Debian con verde openSUSE\n  - fastfetch al abrir terminal\n  - .inputrc con mejoras de readline\n\nLos archivos actuales se respaldan como .bak"; then
        log "Configuracion de shell omitida."
        return 0
    fi

    # ── Contenido de .bashrc ──────────────────────────────────────────────
    local BASHRC_CONTENT
    BASHRC_CONTENT='# ~/.bashrc — Configurado por kde-void-installer
# Basado en la config de Ismael para openSUSE / Void Linux

# Salir si no es interactivo
[[ $- != *i* ]] && return

# ── Prompt estilo Debian con verde openSUSE ──────────────────────────────
PS1='"'"'\[\e[38;5;112m\]\u@\h\[\e[0m\]:\[\e[38;5;33m\]\w\[\e[0m\]\$ '"'"'

# ── Alias utiles ─────────────────────────────────────────────────────────
alias ls='"'"'ls --color=auto'"'"'
alias ll='"'"'ls -lah --color=auto'"'"'
alias la='"'"'ls -A --color=auto'"'"'
alias grep='"'"'grep --color=auto'"'"'
alias xin='"'"'sudo xbps-install -Suy'"'"'
alias xrm='"'"'sudo xbps-remove -R'"'"'
alias xup='"'"'sudo xbps-install -Suy'"'"'
alias xq='"'"'xbps-query -Rs'"'"'

# ── Historial mejorado ───────────────────────────────────────────────────
HISTSIZE=5000
HISTFILESIZE=10000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
shopt -s checkwinsize

# ── Alias de sistema ─────────────────────────────────────────────────────
test -s ~/.alias && . ~/.alias || true

# ── Fastfetch al iniciar terminal ────────────────────────────────────────
if command -v fastfetch &>/dev/null; then
    fastfetch
fi'

    # ── Contenido de .inputrc ─────────────────────────────────────────────
    local INPUTRC_CONTENT
    INPUTRC_CONTENT='# ~/.inputrc — Configurado por kde-void-installer

# Sin campanilla
set bell-style none

# Mostrar completaciones inmediatamente si hay ambiguedad
set show-all-if-ambiguous on
set show-all-if-unmodified on

# Completacion sin distinguir mayusculas/minusculas
set completion-ignore-case on

# Colorear completaciones de archivos
set colored-stats on
set colored-completion-prefix on

# Mostrar caracteres especiales al final (/ para directorios, etc.)
set visible-stats on

# Historial con flechas arriba/abajo filtrando por lo ya escrito
"\e[A": history-search-backward
"\e[B": history-search-forward

# Ctrl+flechas para moverse por palabras
"\e[1;5C": forward-word
"\e[1;5D": backward-word

# end'

    # ── Aplicar a /etc/skel (nuevos usuarios) ─────────────────────────────
    log "  -> Escribiendo en /etc/skel/.bashrc y /etc/skel/.inputrc ..."
    sudo mkdir -p /etc/skel
    [ -f /etc/skel/.bashrc ]  && sudo cp /etc/skel/.bashrc  /etc/skel/.bashrc.bak
    [ -f /etc/skel/.inputrc ] && sudo cp /etc/skel/.inputrc /etc/skel/.inputrc.bak
    printf '%s\n' "$BASHRC_CONTENT"  | sudo tee /etc/skel/.bashrc  > /dev/null
    printf '%s\n' "$INPUTRC_CONTENT" | sudo tee /etc/skel/.inputrc > /dev/null
    log "  -> /etc/skel/.bashrc y /etc/skel/.inputrc actualizados"

    # ── Aplicar al usuario actual ─────────────────────────────────────────
    local BASHRC="$HOME/.bashrc"
    local INPUTRC="$HOME/.inputrc"
    [ -f "$BASHRC" ]  && cp "$BASHRC"  "${BASHRC}.bak"  && log "  -> Respaldo: ${BASHRC}.bak"
    [ -f "$INPUTRC" ] && cp "$INPUTRC" "${INPUTRC}.bak" && log "  -> Respaldo: ${INPUTRC}.bak"
    printf '%s\n' "$BASHRC_CONTENT"  > "$BASHRC"
    printf '%s\n' "$INPUTRC_CONTENT" > "$INPUTRC"
    log "  -> ~/.bashrc y ~/.inputrc del usuario actual configurados"

    # ── Propagar a todos los usuarios del sistema (home en /home) ─────────
    local PROPAGATED=0
    for USER_HOME in /home/*/; do
        [ -d "$USER_HOME" ] || continue
        local TARGET_USER
        TARGET_USER=$(basename "$USER_HOME")
        # Omitir si es el usuario actual (ya hecho arriba)
        [ "$TARGET_USER" = "$USER" ] && continue

        log "  -> Propagando a $TARGET_USER ..."
        [ -f "$USER_HOME/.bashrc" ]  && sudo cp "$USER_HOME/.bashrc"  "$USER_HOME/.bashrc.bak"
        [ -f "$USER_HOME/.inputrc" ] && sudo cp "$USER_HOME/.inputrc" "$USER_HOME/.inputrc.bak"
        printf '%s\n' "$BASHRC_CONTENT"  | sudo tee "$USER_HOME/.bashrc"  > /dev/null
        printf '%s\n' "$INPUTRC_CONTENT" | sudo tee "$USER_HOME/.inputrc" > /dev/null
        sudo chown "$(stat -c '%u:%g' "$USER_HOME")" \
            "$USER_HOME/.bashrc" "$USER_HOME/.inputrc" 2>/dev/null || true
        PROPAGATED=$((PROPAGATED + 1))
    done

    # ── Aplicar tambien a root ─────────────────────────────────────────────
    if [ -d /root ]; then
        log "  -> Propagando a root ..."
        [ -f /root/.bashrc ]  && sudo cp /root/.bashrc  /root/.bashrc.bak
        [ -f /root/.inputrc ] && sudo cp /root/.inputrc /root/.inputrc.bak
        printf '%s\n' "$BASHRC_CONTENT"  | sudo tee /root/.bashrc  > /dev/null
        printf '%s\n' "$INPUTRC_CONTENT" | sudo tee /root/.inputrc > /dev/null
        PROPAGATED=$((PROPAGATED + 1))
    fi

    # ── Instalar fastfetch si no esta ─────────────────────────────────────
    if ! command -v fastfetch &>/dev/null; then
        if yesno "fastfetch no esta instalado.\nDeseas instalarlo ahora?"; then
            sudo xbps-install -Suy fastfetch 2>/dev/null || true
            log "  -> fastfetch instalado"
        fi
    fi

    msgbox "Entorno shell configurado para TODOS los usuarios.\n\nArchivos actualizados en:\n  /etc/skel/.bashrc   (nuevos usuarios)\n  /etc/skel/.inputrc\n  ~/.bashrc  ~/.inputrc  (usuario actual)\n  $PROPAGATED usuario(s) adicionales en /home/ y root\n\nRespaldos guardados como .bak\n\nRecarga con:  source ~/.bashrc"
}

# ─────────────────────────── PASO 3: Hardware / CPU ──────────────────────

detect_hardware() {
    local cpu_info
    cpu_info=$(grep -m1 "vendor_id" /proc/cpuinfo 2>/dev/null || echo "")
    if echo "$cpu_info" | grep -qi "AuthenticAMD"; then
        CPU_VENDOR="amd"
    elif echo "$cpu_info" | grep -qi "GenuineIntel"; then
        CPU_VENDOR="intel"
    else
        CPU_VENDOR="other"
    fi

    if lspci 2>/dev/null | grep -qi "NVIDIA"; then
        GPU_VENDOR="nvidia"
    elif lspci 2>/dev/null | grep -qi "AMD\|ATI\|Radeon"; then
        GPU_VENDOR="amd"
    elif lspci 2>/dev/null | grep -qi "Intel.*Graphics\|Intel.*VGA"; then
        GPU_VENDOR="intel"
    else
        GPU_VENDOR="other"
    fi

    if ls /sys/class/power_supply/BAT* &>/dev/null 2>&1; then
        IS_LAPTOP=1
    fi

    log "  -> Hardware detectado: CPU=$CPU_VENDOR GPU=$GPU_VENDOR LAPTOP=$IS_LAPTOP"
}

step_hardware() {
    detect_hardware

    local cpu_label="Desconocido"
    [ "$CPU_VENDOR" = "amd" ]   && cpu_label="AMD (detectado automaticamente)"
    [ "$CPU_VENDOR" = "intel" ] && cpu_label="Intel (detectado automaticamente)"
    [ "$CPU_VENDOR" = "other" ] && cpu_label="Otro/Desconocido"

    local laptop_str="No detectada"
    [ "$IS_LAPTOP" -eq 1 ] && laptop_str="Si (bateria detectada)"

    local CPU_CHOICE
    CPU_CHOICE=$(radiolist_menu \
        "Seleccion de CPU" \
        "CPU detectada:  $cpu_label\nGPU detectada:  $GPU_VENDOR\nLaptop:         $laptop_str\n\nConfirma o corrige tu tipo de procesador:" \
        "amd"   "AMD  (Ryzen, Threadripper, EPYC...)"          $([ "$CPU_VENDOR" = "amd" ]   && echo ON || echo OFF) \
        "intel" "Intel  (Core i3/i5/i7/i9, Xeon, Atom...)"    $([ "$CPU_VENDOR" = "intel" ] && echo ON || echo OFF) \
        "other" "Otro / No instalar microcódigo"               $([ "$CPU_VENDOR" = "other" ] && echo ON || echo OFF) \
    ) || CPU_CHOICE="$CPU_VENDOR"

    CPU_VENDOR="${CPU_CHOICE:-$CPU_VENDOR}"
    log "CPU confirmada por el usuario: $CPU_VENDOR"

    case "$CPU_VENDOR" in
        amd)
            if yesno "Instalar microcódigo AMD?\n\n  Paquetes: linux-firmware-amd\n\nMejora la estabilidad y seguridad del procesador.\nMuy recomendado para todos los sistemas AMD."; then
                clear
                log "Instalando microcódigo AMD..."
                sudo xbps-install -Suy linux-firmware-amd || true
                msgbox "Microcódigo AMD instalado correctamente."
            fi
            ;;
        intel)
            if yesno "Instalar microcódigo Intel?\n\n  Paquetes: linux-firmware-intel\n\nMejora la estabilidad y seguridad del procesador.\nMuy recomendado para todos los sistemas Intel."; then
                clear
                log "Instalando microcódigo Intel..."
                sudo xbps-install -Suy linux-firmware-intel || true
                msgbox "Microcódigo Intel instalado correctamente."
            fi
            ;;
        *)
            log "No se instala microcódigo para CPU: $CPU_VENDOR"
            ;;
    esac
}

# ─────────────────────────── PASO 3b: Drivers de VIDEO ───────────────────

step_gpu() {
    detect_hardware

    local gpu_label="Desconocido"
    [ "$GPU_VENDOR" = "amd" ]    && gpu_label="AMD / ATI / Radeon (detectado)"
    [ "$GPU_VENDOR" = "nvidia" ] && gpu_label="NVIDIA (detectado)"
    [ "$GPU_VENDOR" = "intel" ]  && gpu_label="Intel Graphics (detectado)"
    [ "$GPU_VENDOR" = "other" ]  && gpu_label="No identificado"

    local GPU_CHOICE
    GPU_CHOICE=$(radiolist_menu \
        "Drivers de Video" \
        "GPU detectada: $gpu_label\n\nSelecciona el driver a instalar para tu tarjeta grafica:" \
        "intel"  "Intel  (HD / UHD / Iris — xf86-video-intel + mesa)"   $([ "$GPU_VENDOR" = "intel" ]  && echo ON || echo OFF) \
        "amd"    "AMD / ATI  (Radeon / RX — mesa + xf86-video-amdgpu)"  $([ "$GPU_VENDOR" = "amd" ]    && echo ON || echo OFF) \
        "nvidia" "NVIDIA  (drivers privativos desde void-repo-nonfree)"  $([ "$GPU_VENDOR" = "nvidia" ] && echo ON || echo OFF) \
        "none"   "Ninguno  (ya instalado o configuracion manual)"        $([ "$GPU_VENDOR" = "other" ]  && echo ON || echo OFF) \
    ) || GPU_CHOICE="$GPU_VENDOR"

    GPU_VENDOR="${GPU_CHOICE:-$GPU_VENDOR}"
    log "GPU seleccionada por el usuario: $GPU_VENDOR"

    local XCONF_DIR="/etc/X11/xorg.conf.d"

    case "$GPU_VENDOR" in

        intel)
            if yesno "Instalar drivers Intel?\n\n  Paquetes:\n    xf86-video-intel   -> Driver Xorg para Intel\n    mesa               -> OpenGL / Vulkan (open source)\n    intel-video-accel  -> Aceleracion de video VA-API\n    vulkan-loader      -> Loader Vulkan\n    mesa-vulkan-intel  -> Backend Vulkan Intel (ANV)\n\nRecomendado para graficos integrados Intel."; then
                clear
                log "Instalando drivers Intel..."
                sudo xbps-install -Suy \
                    xf86-video-intel \
                    mesa \
                    intel-video-accel \
                    vulkan-loader \
                    mesa-vulkan-intel 2>/dev/null || true

                sudo mkdir -p "$XCONF_DIR"
                if [ ! -f "$XCONF_DIR/20-intel.conf" ]; then
                    sudo tee "$XCONF_DIR/20-intel.conf" > /dev/null << 'INTELCFG'
Section "Device"
    Identifier  "Intel Graphics"
    Driver      "intel"
    Option      "TearFree"    "true"
    Option      "AccelMethod" "sna"
EndSection
INTELCFG
                    log "  -> /etc/X11/xorg.conf.d/20-intel.conf creado"
                fi

                groups | grep -qw video || sudo usermod -aG video "$USER" 2>/dev/null || true
                log "  -> Drivers Intel instalados"
                msgbox "Drivers Intel instalados.\n\nArchivos creados:\n  /etc/X11/xorg.conf.d/20-intel.conf\n\nVerifica con:\n  glxinfo | grep renderer\n  vainfo"
            fi
            ;;

        amd)
            if yesno "Instalar drivers AMD / ATI?\n\n  Paquetes:\n    xf86-video-amdgpu  -> Driver Xorg moderno (GCN+)\n    mesa               -> OpenGL / Vulkan (open source)\n    mesa-vaapi         -> Aceleracion VA-API\n    mesa-vdpau         -> Aceleracion VDPAU\n    vulkan-loader      -> Loader Vulkan\n    mesa-vulkan-radeon -> Backend Vulkan AMD (RADV)\n\nRecomendado para Radeon HD 7000+ / RX series."; then
                clear
                log "Instalando drivers AMD..."
                sudo xbps-install -Suy \
                    xf86-video-amdgpu \
                    mesa \
                    mesa-vaapi \
                    mesa-vdpau \
                    vulkan-loader \
                    mesa-vulkan-radeon 2>/dev/null || true

                sudo mkdir -p "$XCONF_DIR"
                if [ ! -f "$XCONF_DIR/20-amdgpu.conf" ]; then
                    sudo tee "$XCONF_DIR/20-amdgpu.conf" > /dev/null << 'AMDCFG'
Section "Device"
    Identifier  "AMD Radeon"
    Driver      "amdgpu"
    Option      "TearFree"  "true"
    Option      "DRI"       "3"
EndSection
AMDCFG
                    log "  -> /etc/X11/xorg.conf.d/20-amdgpu.conf creado"
                fi

                groups | grep -qw video || sudo usermod -aG video "$USER" 2>/dev/null || true
                log "  -> Drivers AMD instalados"
                msgbox "Drivers AMD instalados.\n\nArchivos creados:\n  /etc/X11/xorg.conf.d/20-amdgpu.conf\n\nVerifica con:\n  glxinfo | grep renderer\n  vainfo\n  vdpauinfo"
            fi
            ;;

        nvidia)
            if yesno "Instalar drivers privativos NVIDIA?\n\n  Paquetes:\n    nvidia             -> Driver propietario (recomendado)\n    nvidia-libs        -> Librerias OpenGL 64-bit\n    nvidia-libs-32bit  -> Librerias 32-bit (Steam/Wine)\n    nvidia-dkms        -> Modulo DKMS para kernels custom\n\nRequiere void-repo-nonfree (se habilitara automaticamente)."; then
                clear
                log "Habilitando void-repo-nonfree para NVIDIA..."
                sudo xbps-install -Suy void-repo-nonfree 2>/dev/null || true
                sudo xbps-install -Suy 2>/dev/null || true

                log "Instalando drivers NVIDIA privativos..."
                local NVIDIA_PKGS=(nvidia nvidia-libs nvidia-libs-32bit)
                if xbps-query -Rs linux-headers &>/dev/null 2>&1; then
                    NVIDIA_PKGS+=(nvidia-dkms)
                fi

                sudo xbps-install -Suy "${NVIDIA_PKGS[@]}" 2>/dev/null || {
                    log "  -> Error con paquete completo, intentando sin 32-bit..."
                    sudo xbps-install -Suy nvidia nvidia-libs 2>/dev/null || true
                }

                sudo mkdir -p "$XCONF_DIR"
                if [ ! -f "$XCONF_DIR/10-nvidia.conf" ]; then
                    sudo tee "$XCONF_DIR/10-nvidia.conf" > /dev/null << 'NVIDIACFG'
Section "Device"
    Identifier "NVIDIA"
    Driver     "nvidia"
    Option     "NoLogo" "true"
EndSection
NVIDIACFG
                    log "  -> /etc/X11/xorg.conf.d/10-nvidia.conf creado"
                fi

                if [ -d /etc/dracut.conf.d ]; then
                    sudo tee /etc/dracut.conf.d/nvidia.conf > /dev/null << 'DRACFG'
add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "
DRACFG
                    log "  -> Modulos NVIDIA agregados a dracut"
                fi

                groups | grep -qw video || sudo usermod -aG video "$USER" 2>/dev/null || true
                log "  -> Drivers NVIDIA instalados"
                msgbox "Drivers NVIDIA instalados.\n\nArchivos creados:\n  /etc/X11/xorg.conf.d/10-nvidia.conf\n\nNota: reinicia para cargar el driver.\nVerifica con:\n  nvidia-smi\n  glxinfo | grep renderer"
            fi
            ;;

        none|*)
            log "Drivers de video: sin instalacion (omitido por el usuario)"
            msgbox "Drivers de video omitidos.\nPuedes instalarlos manualmente cuando quieras."
            ;;
    esac
}

# ─────────────────────────── PASO 4: Base ────────────────────────────────

step_base() {
    msgbox "Se instalaran los paquetes base obligatorios:\n\n  xorg + xorg-server\n  xorg-input-drivers + xorg-video-drivers\n  xinit, xinput, xrandr, xset, xsetroot, xdpyinfo\n  wayland\n  dbus\n  NetworkManager\n\nPresiona ENTER para continuar."
    clear
    log "Instalando paquetes base..."
    install_packages "${BASE_PACKAGES[@]}"
    enable_service dbus
    enable_service NetworkManager
    msgbox "Paquetes base instalados correctamente."
}

# ─────────────────────────── PASO 5: Xinput / Entrada ────────────────────

step_xinput() {
    RAW=$(checklist_menu \
        "Dispositivos de Entrada (xinput / libinput)" \
        "Configura los drivers para raton, teclado y touchpad.\nlibinput es el driver moderno recomendado.\nxf86-input-synaptics solo para touchpads muy antiguos:" \
        "${XINPUT_OPTS[@]}") || return 0

    RAW=${RAW//\"/}
    read -r -a SELECTED <<< "$RAW"

    [ ${#SELECTED[@]} -eq 0 ] && return 0

    clear
    log "Instalando drivers de entrada: ${SELECTED[*]}"
    install_packages "${SELECTED[@]}"

    # Crear configuración libinput en xorg.conf.d
    if [[ " ${SELECTED[*]} " == *" xf86-input-libinput "* ]] || \
       [[ " ${SELECTED[*]} " == *" libinput "* ]]; then
        local XCONF_DIR="/etc/X11/xorg.conf.d"
        sudo mkdir -p "$XCONF_DIR"
        if [ ! -f "$XCONF_DIR/40-libinput.conf" ]; then
            sudo tee "$XCONF_DIR/40-libinput.conf" > /dev/null << 'EOF'
# Configuracion libinput generada por kde-void-installer
# Para ver dispositivos disponibles: xinput list
# Para ver propiedades: xinput list-props <id>

Section "InputClass"
    Identifier "libinput pointer catchall"
    MatchIsPointer "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
    Option "AccelProfile" "adaptive"
EndSection

Section "InputClass"
    Identifier "libinput keyboard catchall"
    MatchIsKeyboard "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
EndSection

Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
    Option "Tapping" "on"
    Option "TappingDrag" "on"
    Option "NaturalScrolling" "true"
    Option "TappingButtonMap" "lrm"
    Option "DisableWhileTyping" "true"
EndSection
EOF
            log "  -> /etc/X11/xorg.conf.d/40-libinput.conf creado"
        else
            log "  -> 40-libinput.conf ya existe, no se sobreescribio"
        fi
    fi

    # Crear ~/.xinitrc si no existe
    if [ ! -f "$HOME/.xinitrc" ]; then
        cat > "$HOME/.xinitrc" << 'EOF'
#!/bin/sh
# ~/.xinitrc generado por kde-void-installer
# Para iniciar KDE Plasma en X11 sin SDDM: startx

# Opcional: configurar touchpad via xinput al inicio
# xinput set-prop "nombre-del-touchpad" "libinput Tapping Enabled" 1
# xinput set-prop "nombre-del-touchpad" "libinput Natural Scrolling Enabled" 1

exec startplasma-x11
EOF
        chmod +x "$HOME/.xinitrc"
        log "  -> ~/.xinitrc creado apuntando a startplasma-x11"
    fi

    msgbox "Drivers de entrada instalados.\n\nConfiguracion libinput en:\n  /etc/X11/xorg.conf.d/40-libinput.conf\n\nXinitrc en:\n  ~/.xinitrc  (para usar 'startx' sin SDDM)\n\nComandos utiles:\n  xinput list              -> ver dispositivos\n  xinput list-props <id>   -> propiedades de un dispositivo"
}

# ─────────────────────────── PASO 6: Audio ───────────────────────────────

step_audio() {
    RAW=$(checklist_menu \
        "Audio — PipeWire" \
        "PipeWire es el servidor de audio recomendado para Void + KDE.\nSe configurara automaticamente segun la documentacion oficial:" \
        "${AUDIO_OPTS[@]}") || return 0

    RAW=${RAW//\"/}
    read -r -a SELECTED <<< "$RAW"

    [ ${#SELECTED[@]} -eq 0 ] && return 0

    clear
    log "Instalando audio: ${SELECTED[*]}"
    install_packages "${SELECTED[@]}"

    if [[ " ${SELECTED[*]} " == *" pipewire "* ]]; then
        configure_pipewire
    fi

    if [[ " ${SELECTED[*]} " == *" alsa-pipewire "* ]]; then
        configure_alsa_pipewire
    fi

    if [[ " ${SELECTED[*]} " == *" libjack-pipewire "* ]]; then
        configure_jack_pipewire
    fi

    msgbox "Audio instalado y configurado correctamente.\n\nPara verificar tras reiniciar:\n  pipewire\n  wpctl status\n  pactl info"
}

# ── Configura PipeWire + WirePlumber segun doc oficial de Void ─────────────
configure_pipewire() {
    log "Configurando PipeWire + WirePlumber..."

    # 1. Enlace de WirePlumber (session manager obligatorio)
    sudo mkdir -p /etc/pipewire/pipewire.conf.d
    if [ ! -f /etc/pipewire/pipewire.conf.d/10-wireplumber.conf ]; then
        sudo ln -s /usr/share/examples/wireplumber/10-wireplumber.conf             /etc/pipewire/pipewire.conf.d/
        log "  -> WirePlumber enlazado en /etc/pipewire/pipewire.conf.d/"
    fi

    # 2. Interfaz PulseAudio (necesaria para la mayoria de apps)
    if [ ! -f /etc/pipewire/pipewire.conf.d/20-pipewire-pulse.conf ]; then
        sudo ln -s /usr/share/examples/pipewire/20-pipewire-pulse.conf             /etc/pipewire/pipewire.conf.d/
        log "  -> pipewire-pulse enlazado"
    fi

    # 3. Remover pulseaudio si esta instalado (conflicto)
    if xbps-query pulseaudio &>/dev/null 2>&1; then
        log "  -> PulseAudio detectado, removiendo para evitar conflicto..."
        sudo xbps-remove -R pulseaudio 2>/dev/null || true
        log "  -> PulseAudio removido"
    fi

    # 4. Asegurar que el usuario este en el grupo audio y video
    if ! groups | grep -qw audio; then
        sudo usermod -aG audio "$USER"
        log "  -> Usuario $USER agregado al grupo audio"
    fi
    if ! groups | grep -qw video; then
        sudo usermod -aG video "$USER"
        log "  -> Usuario $USER agregado al grupo video"
    fi

    # 5. Autostart via XDG (KDE lo respeta automaticamente)
    local AUTOSTART_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
    mkdir -p "$AUTOSTART_DIR"
    if [ ! -f "$AUTOSTART_DIR/pipewire.desktop" ] &&        [ -f /usr/share/applications/pipewire.desktop ]; then
        ln -s /usr/share/applications/pipewire.desktop "$AUTOSTART_DIR/"
        log "  -> pipewire.desktop enlazado en autostart"
    fi

    log "  -> PipeWire configurado correctamente"
}

# ── Configura integracion ALSA con PipeWire ───────────────────────────────
configure_alsa_pipewire() {
    log "Configurando ALSA para usar PipeWire..."
    sudo mkdir -p /etc/alsa/conf.d
    if [ ! -f /etc/alsa/conf.d/50-pipewire.conf ]; then
        sudo ln -s /usr/share/alsa/alsa.conf.d/50-pipewire.conf             /etc/alsa/conf.d/
        log "  -> 50-pipewire.conf enlazado"
    fi
    if [ ! -f /etc/alsa/conf.d/99-pipewire-default.conf ]; then
        sudo ln -s /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf             /etc/alsa/conf.d/
        log "  -> 99-pipewire-default.conf enlazado (dispositivo ALSA por defecto)"
    fi
}

# ── Configura interfaz JACK via PipeWire ──────────────────────────────────
configure_jack_pipewire() {
    log "Configurando JACK via PipeWire..."
    if [ ! -f /etc/ld.so.conf.d/pipewire-jack.conf ]; then
        echo "/usr/lib/pipewire-0.3/jack" |             sudo tee /etc/ld.so.conf.d/pipewire-jack.conf > /dev/null
        sudo ldconfig
        log "  -> JACK redirigido a PipeWire via ld.so"
    fi
}

# ─────────────────────────── PASO 7: KDE nucleo ──────────────────────────

# Instala el metapaquete KDE con fallback kde5 <-> kde-plasma
install_kde_meta() {
    if sudo xbps-install -Suy kde5 2>/dev/null; then
        log "  -> Metapaquete instalado: kde5"
    elif sudo xbps-install -Suy kde-plasma 2>/dev/null; then
        log "  -> Metapaquete instalado: kde-plasma"
    else
        log "  -> ADVERTENCIA: no se pudo instalar kde5 ni kde-plasma"
    fi
}

step_plasma_core() {
    RAW=$(checklist_menu \
        "KDE Plasma 6 — Nucleo" \
        "Selecciona los componentes principales de KDE Plasma 6:" \
        "${PLASMA_CORE_OPTS[@]}") || return 0

    RAW=${RAW//\"/}
    read -r -a SELECTED <<< "$RAW"

    [ ${#SELECTED[@]} -eq 0 ] && return 0

    clear
    log "Instalando KDE Plasma nucleo: ${SELECTED[*]}"
    # Si se selecciono el metapaquete principal, usar fallback kde5/kde-plasma
    local FILTERED=()
    local INSTALL_META=0
    for pkg in "${SELECTED[@]}"; do
        if [[ "$pkg" == "kde5" || "$pkg" == "kde-plasma" ]]; then
            INSTALL_META=1
        else
            FILTERED+=("$pkg")
        fi
    done
    [ $INSTALL_META -eq 1 ] && install_kde_meta
    [ ${#FILTERED[@]} -gt 0 ] && install_packages "${FILTERED[@]}"

    if [[ " ${SELECTED[*]} " == *" sddm "* ]]; then
        enable_service sddm
        log "  -> SDDM habilitado como gestor de inicio de sesion"
    fi
    msgbox "KDE Plasma instalado correctamente."
}

# ─────────────────────────── PASO 8: Apps KDE ────────────────────────────

step_plasma_apps() {
    RAW=$(checklist_menu \
        "Aplicaciones KDE" \
        "Selecciona las aplicaciones KDE que deseas instalar:" \
        "${PLASMA_APPS_OPTS[@]}") || return 0

    RAW=${RAW//\"/}
    read -r -a SELECTED <<< "$RAW"

    [ ${#SELECTED[@]} -eq 0 ] && return 0

    clear
    log "Instalando aplicaciones KDE: ${SELECTED[*]}"
    install_packages "${SELECTED[@]}"
    msgbox "Aplicaciones KDE instaladas correctamente."
}

# ─────────────────────────── PASO 9: Opcionales ──────────────────────────

step_plasma_optional() {
    RAW=$(checklist_menu \
        "Herramientas Opcionales para Plasma" \
        "Utilidades y complementos opcionales para KDE Plasma:" \
        "${PLASMA_OPTIONAL_OPTS[@]}") || return 0

    RAW=${RAW//\"/}
    read -r -a SELECTED <<< "$RAW"

    [ ${#SELECTED[@]} -eq 0 ] && return 0

    clear
    log "Instalando herramientas opcionales: ${SELECTED[*]}"
    install_packages "${SELECTED[@]}"

    if [[ " ${SELECTED[*]} " == *" ufw "* ]]; then
        sudo ufw enable 2>/dev/null || true
        enable_service ufw 2>/dev/null || true
        log "  -> UFW habilitado"
    fi
    msgbox "Herramientas opcionales instaladas correctamente."
}

# ─────────────────────────── PASO 10: TLP / Energia ──────────────────────

step_power() {
    local power_msg="Gestion avanzada de energia para tu sistema."
    local tlp_note=""
    if [ "$IS_LAPTOP" -eq 1 ]; then
        power_msg="Laptop detectada. TLP es muy recomendado para\nmaximizar la duracion de bateria y reducir el calor."
    fi

    case "$CPU_VENDOR" in
        intel) tlp_note="thermald es especialmente util para CPUs Intel." ;;
        amd)   tlp_note="tlp funciona excelente con CPUs AMD Ryzen." ;;
    esac

    if ! yesno "Instalar gestion de energia?\n\n$power_msg\n$tlp_note\n\n  tlp      -> Daemon de ahorro de energia\n  tlp-rdw  -> Radio Device Wizard (WiFi/BT al suspender)\n  tlpui    -> Interfaz grafica para TLP\n  powertop -> Monitor de consumo energetico"; then
        log "Gestion de energia omitida."
        return 0
    fi

    RAW=$(checklist_menu \
        "Gestion de Energia — TLP" \
        "Selecciona los componentes de energia a instalar:" \
        "${TLP_OPTS[@]}") || return 0

    RAW=${RAW//\"/}
    read -r -a SELECTED <<< "$RAW"

    [ ${#SELECTED[@]} -eq 0 ] && return 0

    clear
    log "Instalando gestion de energia: ${SELECTED[*]}"
    install_packages "${SELECTED[@]}"

    # Habilitar TLP, deshabilitar power-profiles-daemon (incompatible)
    if [[ " ${SELECTED[*]} " == *" tlp "* ]]; then
        # TLP no usa runit en Void; se activa via udev al reiniciar
        log "  -> TLP instalado. Se activara automaticamente al reiniciar."
        if [ -e "/var/service/power-profiles-daemon" ]; then
            log "  -> Deshabilitando power-profiles-daemon (incompatible con TLP)..."
            sudo rm -f /var/service/power-profiles-daemon
        fi
        log "  -> TLP habilitado"
    fi

    if [[ " ${SELECTED[*]} " == *" acpid "* ]]; then
        enable_service acpid
    fi

    # Mostrar sugerencias de configuracion segun CPU
    if [[ " ${SELECTED[*]} " == *" tlp "* ]]; then
        case "$CPU_VENDOR" in
            amd)
                whiptail --title "TLP — Configuracion AMD" --backtitle "$BACKTITLE" --msgbox \
"TLP instalado. Configuracion recomendada para CPU AMD\n(agrega a /etc/tlp.conf):\n
  CPU_SCALING_GOVERNOR_ON_AC=performance
  CPU_SCALING_GOVERNOR_ON_BAT=powersave
  CPU_ENERGY_PERF_POLICY_ON_BAT=power
  CPU_ENERGY_PERF_POLICY_ON_AC=performance
  PLATFORM_PROFILE_ON_AC=performance
  PLATFORM_PROFILE_ON_BAT=low-power
  RADEON_DPM_STATE_ON_AC=performance
  RADEON_DPM_STATE_ON_BAT=battery\n
Edita con:  sudo nano /etc/tlp.conf
O usa tlpui si lo instalaste." \
                22 62
                ;;
            intel)
                whiptail --title "TLP — Configuracion Intel" --backtitle "$BACKTITLE" --msgbox \
"TLP instalado. Configuracion recomendada para CPU Intel\n(agrega a /etc/tlp.conf):\n
  CPU_SCALING_GOVERNOR_ON_AC=performance
  CPU_SCALING_GOVERNOR_ON_BAT=powersave
  CPU_ENERGY_PERF_POLICY_ON_BAT=power
  CPU_ENERGY_PERF_POLICY_ON_AC=performance
  CPU_HWP_DYN_BOOST_ON_AC=1
  CPU_HWP_DYN_BOOST_ON_BAT=0
  INTEL_GPU_MIN_FREQ_ON_BAT=0
  INTEL_GPU_MAX_FREQ_ON_BAT=500\n
Edita con:  sudo nano /etc/tlp.conf
O usa tlpui si lo instalaste." \
                22 62
                ;;
        esac
    fi

    msgbox "Gestion de energia instalada.\n\nComandos utiles:\n  sudo tlp start     -> Iniciar TLP\n  sudo tlp-stat      -> Ver estado\n  sudo tlp-stat -b   -> Estado de bateria\n  sudo tlp-stat -p   -> Perfiles de CPU"
}

# ─────────────────────────── PASO 11: Timeshift ──────────────────────────

step_timeshift() {
    if ! yesno "Instalar Timeshift para instantaneas del sistema?\n\nTimeshift crea copias de seguridad automaticas del sistema\nusando rsync o snapshots BTRFS.\n\nMuy util para recuperarse de actualizaciones que rompan el sistema."; then
        log "Timeshift omitido."
        return 0
    fi

    # Elegir backend
    local TS_BACKEND
    TS_BACKEND=$(radiolist_menu \
        "Timeshift — Tipo de Instantaneas" \
        "Elige el metodo de snapshots:\n\nBTRFS requiere que / este formateado en BTRFS.\nrsync funciona con cualquier filesystem (ext4, xfs, etc)." \
        "rsync" "rsync  -> Compatible con ext4, xfs, btrfs (recomendado)" ON \
        "btrfs" "BTRFS  -> Snapshots nativos, mas rapido (solo en BTRFS)" OFF \
    ) || TS_BACKEND="rsync"
    TS_BACKEND="${TS_BACKEND:-rsync}"

    # Sugerir la mejor ruta disponible
    local DEFAULT_PATH="/"
    # Si hay /home en particion separada, recomendarlo para no saturar /
    if mountpoint -q /home 2>/dev/null; then
        DEFAULT_PATH="/home"
    fi
    # Si hay disco extra montado, usarlo
    for mnt in /mnt /data /backup /storage; do
        if mountpoint -q "$mnt" 2>/dev/null; then
            DEFAULT_PATH="$mnt"
            break
        fi
    done

    # Mostrar particiones disponibles para que el usuario elija bien
    local PARTITIONS_INFO
    PARTITIONS_INFO=$(df -h --output=target,size,avail,pcent 2>/dev/null \
        | grep -v "tmpfs\|udev\|/boot\|/run\|Filesystem" \
        | awk '{printf "  %-20s tam:%-6s libre:%-6s uso:%s\n", $1,$2,$3,$4}' \
        | head -8 || echo "  (no se pudieron listar las particiones)")

    local SNAP_PATH
    SNAP_PATH=$(whiptail --title "Timeshift — Ruta de Instantaneas" \
        --backtitle "$BACKTITLE" \
        --inputbox \
"Ruta donde se guardaran las instantaneas del sistema.

Recomendacion: usa una particion separada o disco externo.
Espacio recomendado: 20-50 GB libres minimo.

Particiones disponibles:
$PARTITIONS_INFO

Ruta (puedes escribir cualquier ruta existente):" \
        20 68 "$DEFAULT_PATH" \
        3>&1 1>&2 2>&3) || SNAP_PATH="$DEFAULT_PATH"

    SNAP_PATH="${SNAP_PATH:-$DEFAULT_PATH}"

    # Crear el directorio si no existe
    if [ ! -d "$SNAP_PATH" ]; then
        if yesno "La ruta '$SNAP_PATH' no existe.\nDeseas crearla ahora?"; then
            sudo mkdir -p "$SNAP_PATH"
            log "  -> Directorio creado: $SNAP_PATH"
        else
            SNAP_PATH="/"
            log "  -> Usando / como ruta de snapshots"
        fi
    fi

    # Advertir si hay poco espacio
    local AVAIL_GB
    AVAIL_GB=$(df -BG "$SNAP_PATH" 2>/dev/null | awk 'NR==2 {gsub("G","",$4); print $4}' || echo "0")
    if [ "$AVAIL_GB" != "0" ] && [ "$AVAIL_GB" -lt 15 ] 2>/dev/null; then
        whiptail --title "Advertencia — Poco espacio" --backtitle "$BACKTITLE" --msgbox \
            "Advertencia: Solo hay ${AVAIL_GB} GB disponibles en $SNAP_PATH.\n\nTimeshift recomienda al menos 15-20 GB libres.\nPuedes cambiar la ruta mas tarde en la interfaz grafica de Timeshift." \
            10 62
    fi

    # Instalar Timeshift
    clear
    log "Instalando Timeshift (backend=$TS_BACKEND, ruta=$SNAP_PATH)..."
    sudo xbps-install -Suy timeshift 2>/dev/null || {
        log "  -> timeshift no encontrado en repos estandar."
        if [ "$TS_BACKEND" = "btrfs" ]; then
            log "  -> Instalando snapper como alternativa BTRFS..."
            sudo xbps-install -Suy snapper grub-btrfs 2>/dev/null || true
        fi
    }

    # Crear estructura de directorios de snapshots
    local TIMESHIFT_DIR="$SNAP_PATH/timeshift"
    local SNAP_DIR="$TIMESHIFT_DIR/snapshots"
    sudo mkdir -p "$SNAP_DIR"
    sudo chmod 700 "$TIMESHIFT_DIR"
    log "  -> Estructura creada: $SNAP_DIR"

    # Escribir configuracion base de Timeshift
    local TS_CONF_DIR="/etc/timeshift"
    sudo mkdir -p "$TS_CONF_DIR"
    sudo tee "$TS_CONF_DIR/timeshift.json" > /dev/null << EOF
{
  "backup_device_uuid" : "",
  "parent_device_uuid" : "",
  "do_first_run_checks" : "false",
  "btrfs_mode" : "$([ "$TS_BACKEND" = "btrfs" ] && echo true || echo false)",
  "include_btrfs_home_for_backup" : "false",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "false",
  "schedule_weekly" : "true",
  "schedule_daily" : "true",
  "schedule_hourly" : "false",
  "schedule_boot" : "true",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "5",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "exclude" : [
    "+/root/***",
    "+/home/***",
    "-/proc/***",
    "-/sys/***",
    "-/dev/***",
    "-/tmp/***",
    "-/run/***",
    "-/mnt/***",
    "-/media/***",
    "-/lost+found"
  ],
  "exclude-apps" : []
}
EOF
    log "  -> Configuracion guardada en $TS_CONF_DIR/timeshift.json"

    msgbox "Timeshift instalado correctamente.\n\nConfiguracion:\n  Backend:          $TS_BACKEND\n  Ruta snapshots:   $SNAP_PATH/timeshift/snapshots\n  Diarios:          5 snapshots\n  Semanales:        3 snapshots\n  Al inicio:        5 snapshots\n\nAbre Timeshift desde el menu de aplicaciones\npara seleccionar el dispositivo de destino\ny crear el primer snapshot manualmente."
}

# ─────────────────────────── PASO 12: PIM ────────────────────────────────

step_pim() {
    if yesno "Instalar herramientas PIM de KDE?\n\n(Correo, calendario, contactos con Kontact/Akonadi)\n\nSon opcionales y tienen muchas dependencias."; then
        RAW=$(checklist_menu \
            "KDE PIM — Informacion Personal" \
            "Selecciona los componentes PIM de KDE:" \
            "${PLASMA_PIM_OPTS[@]}") || return 0

        RAW=${RAW//\"/}
        read -r -a SELECTED <<< "$RAW"

        [ ${#SELECTED[@]} -eq 0 ] && return 0

        clear
        log "Instalando KDE PIM: ${SELECTED[*]}"
        install_packages "${SELECTED[@]}"
        msgbox "Componentes PIM instalados correctamente."
    fi
}

# ─────────────────────────── PASO 13: Extras ─────────────────────────────

step_extra() {
    RAW=$(checklist_menu \
        "Extras" \
        "Dependencias adicionales opcionales:" \
        "${PYTHON_OPTS[@]}") || return 0

    RAW=${RAW//\"/}
    read -r -a SELECTED <<< "$RAW"

    [ ${#SELECTED[@]} -eq 0 ] && return 0

    clear
    log "Instalando extras: ${SELECTED[*]}"
    install_packages "${SELECTED[@]}"
    msgbox "Extras instalados correctamente."
}

# ─────────────────────────── PASO final: Reiniciar ───────────────────────

step_finish() {
    if yesno "Instalacion completada.\n\nSe recomienda reiniciar el sistema para aplicar\ntodos los cambios (SDDM, microcódigo, TLP, etc).\n\nDeseas reiniciar ahora?"; then
        log "Usuario eligio reiniciar."
        sudo reboot
    else
        msgbox "Puedes reiniciar mas tarde con:\n  sudo reboot\n\nLog de instalacion guardado en:\n  $LOGFILE"
    fi
}

# ─────────────────────────── Modo Express ────────────────────────────────

install_express() {
    _EXPRESS_MODE=1
    log "=== MODO EXPRESS: Instalacion completa de KDE Plasma ==="

    detect_hardware

    local EXTRA_UCODE=()
    case "$CPU_VENDOR" in
        amd)   EXTRA_UCODE=(linux-firmware-amd) ;;
        intel) EXTRA_UCODE=(linux-firmware-intel) ;;
    esac

    # ── Seleccion interactiva de GPU (antes del gauge) ────────────────────
    local gpu_label="No identificada"
    [ "$GPU_VENDOR" = "intel" ]  && gpu_label="Intel Graphics (detectado)"
    [ "$GPU_VENDOR" = "amd" ]    && gpu_label="AMD / Radeon (detectado)"
    [ "$GPU_VENDOR" = "nvidia" ] && gpu_label="NVIDIA (detectado)"
    [ "$GPU_VENDOR" = "other" ]  && gpu_label="No identificada / VM"

    local GPU_EXPRESS_CHOICE
    GPU_EXPRESS_CHOICE=$(radiolist_menu \
        "Drivers de Video — Modo Express" \
        "GPU detectada: $gpu_label\n\nSelecciona los drivers a instalar.\nSi usas maquina virtual elige 'Ninguno / VM':" \
        "intel"  "Intel  (HD/UHD/Iris — xf86-video-intel + mesa)"  $([ "$GPU_VENDOR" = "intel" ]  && echo ON || echo OFF) \
        "amd"    "AMD / ATI  (Radeon/RX — xf86-video-amdgpu + mesa)" $([ "$GPU_VENDOR" = "amd" ]  && echo ON || echo OFF) \
        "nvidia" "NVIDIA  (drivers privativos, void-repo-nonfree)"   $([ "$GPU_VENDOR" = "nvidia" ] && echo ON || echo OFF) \
        "none"   "Ninguno / VM  (sin driver especifico)"             $([ "$GPU_VENDOR" = "other" ]  && echo ON || echo OFF) \
    ) || GPU_EXPRESS_CHOICE="${GPU_VENDOR:-none}"
    GPU_EXPRESS_CHOICE="${GPU_EXPRESS_CHOICE:-none}"
    log "GPU seleccionada en Express: $GPU_EXPRESS_CHOICE"

    # ── Archivos temporales ───────────────────────────────────────────────
    local GAUGE_PIPE ERR_LOG
    GAUGE_PIPE=$(mktemp -u /tmp/kde-gauge-XXXXXX)
    ERR_LOG=$(mktemp /tmp/kde-err-XXXXXX.log)
    mkfifo "$GAUGE_PIPE"

    # ── Funcion auxiliar: instala solo los paquetes NO instalados aun ───────
    _xbps() {
        local to_install=()
        for pkg in "$@"; do
            # xbps-query -l muestra "ii <pkgver>" para instalados
            if ! xbps-query "$pkg" &>/dev/null 2>&1; then
                to_install+=("$pkg")
            fi
        done
        if [ ${#to_install[@]} -eq 0 ]; then
            printf '[SKIP %s] Ya instalados: %s\n' "$(date '+%H:%M:%S')" "$*" >> "$ERR_LOG"
            return 0
        fi
        local rc=0
        sudo xbps-install -y "${to_install[@]}" >> "$ERR_LOG" 2>&1 || rc=$?
        if [ $rc -ne 0 ]; then
            printf '[ERROR %s] xbps-install %s (rc=%s)\n' \
                "$(date '+%H:%M:%S')" "${to_install[*]}" "$rc" >> "$ERR_LOG"
        fi
        return 0   # nunca abortar el express por un paquete fallido
    }

    # ── Lanzar whiptail PRIMERO (abre el lado lector del FIFO) ───────────
    # El open() del escritor bloquea hasta que haya un lector; por eso
    # whiptail debe arrancar antes de que abramos el FD 9 para escribir.
    whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
        --gauge "Preparando instalacion..." 8 70 0 < "$GAUGE_PIPE" &
    local GAUGE_PID=$!

    # Ahora abrimos el lado escritor del FIFO sin riesgo de bloqueo
    exec 9>"$GAUGE_PIPE"

    # Funcion auxiliar: escribe progreso al FD persistente
    _gp() {
        printf '%s\n# %s\n' "$1" "$2" >&9
    }


    # ── Instalacion real ──────────────────────────────────────────────────
    _gp 3  "Habilitando repos privativos (nonfree + multilib)..."
    _xbps void-repo-nonfree void-repo-multilib

    _gp 6  "Actualizando lista de paquetes..."
    sudo xbps-install -Suy >> "$ERR_LOG" 2>&1 || true

    _gp 10 "Instalando xorg-server..."
    _xbps xorg-server xinit

    _gp 13 "Instalando drivers xorg..."
    _xbps xorg-input-drivers xorg-video-drivers

    _gp 15 "Instalando drivers de video ($GPU_EXPRESS_CHOICE)..."
    case "$GPU_EXPRESS_CHOICE" in
        intel)
            _xbps xf86-video-intel mesa intel-video-accel vulkan-loader mesa-vulkan-intel
            ;;
        amd)
            _xbps xf86-video-amdgpu mesa mesa-vaapi mesa-vdpau vulkan-loader mesa-vulkan-radeon
            ;;
        nvidia)
            # Asegurar nonfree habilitado
            sudo xbps-install -Suy void-repo-nonfree >> "$ERR_LOG" 2>&1 || true
            sudo xbps-install -Suy >> "$ERR_LOG" 2>&1 || true
            _xbps nvidia nvidia-libs nvidia-libs-32bit
            local XCONF_DIR_EXP="/etc/X11/xorg.conf.d"
            sudo mkdir -p "$XCONF_DIR_EXP"
            if [ ! -f "$XCONF_DIR_EXP/10-nvidia.conf" ]; then
                sudo tee "$XCONF_DIR_EXP/10-nvidia.conf" > /dev/null << 'NVEXPRESS'
Section "Device"
    Identifier "NVIDIA"
    Driver     "nvidia"
    Option     "NoLogo" "true"
EndSection
NVEXPRESS
            fi
            ;;
        none|*)
            log "  -> Drivers de video omitidos (VM o eleccion del usuario)"
            ;;
    esac

    _gp 16 "Instalando utilidades X11..."
    _xbps xinput xrandr xset xsetroot xdpyinfo

    _gp 19 "Instalando Wayland y D-Bus..."
    _xbps wayland dbus

    _gp 22 "Instalando NetworkManager..."
    _xbps NetworkManager

    _gp 25 "Instalando microcodigo CPU ($CPU_VENDOR)..."
    if [ ${#EXTRA_UCODE[@]} -gt 0 ]; then
        _xbps "${EXTRA_UCODE[@]}"
    fi

    _gp 29 "Instalando libinput..."
    _xbps libinput xf86-input-libinput

    _gp 33 "Instalando utilidades de entrada..."
    _xbps xinput xset setxkbmap

    _gp 37 "Instalando PipeWire..."
    _xbps pipewire

    _gp 40 "Instalando integracion ALSA + audio..."
    _xbps alsa-pipewire alsa-utils pavucontrol-qt pulseaudio-utils

    _gp 42 "Configurando PipeWire + WirePlumber..."
    # Enlace WirePlumber (session manager)
    sudo mkdir -p /etc/pipewire/pipewire.conf.d
    [ ! -f /etc/pipewire/pipewire.conf.d/10-wireplumber.conf ] &&         sudo ln -sf /usr/share/examples/wireplumber/10-wireplumber.conf             /etc/pipewire/pipewire.conf.d/ 2>>"$ERR_LOG" || true

    # Interfaz PulseAudio
    [ ! -f /etc/pipewire/pipewire.conf.d/20-pipewire-pulse.conf ] &&         sudo ln -sf /usr/share/examples/pipewire/20-pipewire-pulse.conf             /etc/pipewire/pipewire.conf.d/ 2>>"$ERR_LOG" || true

    # Remover PulseAudio si existe (conflicto)
    xbps-query pulseaudio &>/dev/null 2>&1 &&         sudo xbps-remove -R pulseaudio >> "$ERR_LOG" 2>&1 || true

    # ALSA via PipeWire
    sudo mkdir -p /etc/alsa/conf.d
    [ ! -f /etc/alsa/conf.d/50-pipewire.conf ] &&         sudo ln -sf /usr/share/alsa/alsa.conf.d/50-pipewire.conf             /etc/alsa/conf.d/ 2>>"$ERR_LOG" || true
    [ ! -f /etc/alsa/conf.d/99-pipewire-default.conf ] &&         sudo ln -sf /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf             /etc/alsa/conf.d/ 2>>"$ERR_LOG" || true

    # Grupos audio y video
    groups | grep -qw audio || sudo usermod -aG audio "$USER" 2>>"$ERR_LOG" || true
    groups | grep -qw video || sudo usermod -aG video "$USER" 2>>"$ERR_LOG" || true

    # Autostart XDG
    mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
    [ ! -f "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/pipewire.desktop" ] &&     [ -f /usr/share/applications/pipewire.desktop ] &&         ln -sf /usr/share/applications/pipewire.desktop             "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/" 2>>"$ERR_LOG" || true

    _gp 50 "Detectando metapaquete KDE disponible..."
    local KDE_META=""
    # Intentar detectar cual nombre existe en el repositorio
    if xbps-query -Rp pkgver kde-plasma 2>/dev/null | grep -q "kde-plasma"; then
        KDE_META="kde-plasma"
    elif xbps-query -Rp pkgver kde5 2>/dev/null | grep -q "kde5"; then
        KDE_META="kde5"
    fi
    log "  -> Metapaquete KDE detectado: ${KDE_META:-ninguno}"

    _gp 53 "Instalando KDE Plasma..."
    if [ -n "$KDE_META" ]; then
        _xbps "$KDE_META"
    else
        # Fallback: instalar componentes esenciales directamente
        log "  -> Metapaquete no encontrado, instalando componentes individuales..."
        _xbps plasma-desktop plasma-pa kscreen kwin
    fi

    _gp 63 "Instalando apps KDE esenciales..."
    _xbps dolphin konsole ark spectacle gwenview

    _gp 68 "Instalando integracion KDE..."
    _xbps plasma-integration breeze xdg-desktop-portal-kde

    _gp 71 "Instalando Wayland + SDDM..."
    _xbps plasma-wayland-protocols kwalletmanager sddm

    _gp 74 "Instalando miniaturas y extras..."
    _xbps kdeconnect kcalc kdegraphics-thumbnailers ffmpegthumbs

    _gp 77 "Instalando kwrite, Discover y utilidades..."
    _xbps kwrite vlc discover packagekit-qt5 flatpak-kcm

    _gp 82 "Instalando TLP (ahorro de energia)..."
    _xbps tlp tlp-rdw tlp-pd

    _gp 90 "Habilitando servicios..."
    enable_service dbus
    enable_service NetworkManager
    # TLP en Void Linux no usa runit service; se activa via udev automaticamente
    # tras reiniciar. Solo verificar que este instalado.
    if command -v tlp &>/dev/null; then
        log "  -> TLP instalado (se activara al reiniciar via udev)"
    fi
    enable_service sddm

    _gp 95 "Creando configuraciones..."
    if [ ! -f "$HOME/.xinitrc" ]; then
        printf '#!/bin/sh\nexec startplasma-x11\n' > "$HOME/.xinitrc"
        chmod +x "$HOME/.xinitrc"
    fi
    local XCONF_DIR="/etc/X11/xorg.conf.d"
    if [ ! -f "$XCONF_DIR/40-libinput.conf" ]; then
        sudo mkdir -p "$XCONF_DIR"
        sudo tee "$XCONF_DIR/40-libinput.conf" > /dev/null << 'LIBINPUT'
Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "NaturalScrolling" "true"
EndSection
LIBINPUT
    fi
    [ -e "/var/service/power-profiles-daemon" ] && \
        sudo rm -f /var/service/power-profiles-daemon || true

    _gp 100 "Completado."
    sleep 0.5   # dejar que whiptail muestre el 100%

    # ── Cerrar FD y pipe; terminar gauge ──────────────────────────────────
    exec 9>&-                          # cerrar FD → whiptail recibe EOF y sale
    wait "$GAUGE_PID" 2>/dev/null || true
    rm -f "$GAUGE_PIPE"

    # ── Mostrar log si hubo errores no fatales ────────────────────────────
    clear
    if grep -q '^\[ERROR' "$ERR_LOG" 2>/dev/null; then
        local ERR_COUNT
        ERR_COUNT=$(grep -c '^\[ERROR' "$ERR_LOG")
        whiptail --title "Advertencias de instalacion" --backtitle "$BACKTITLE" \
            --scrolltext --msgbox \
"Se encontraron $ERR_COUNT advertencia(s) durante la instalacion.
Los paquetes que fallaron pueden no estar disponibles o ya estaban instalados.

$(head -40 "$ERR_LOG")

El log completo se guardo en: $LOGFILE" \
            $HEIGHT $WIDTH
    fi
    rm -f "$ERR_LOG"

    _EXPRESS_MODE=0
    log "=== Modo Express completado ==="

    # Configurar entorno shell
    step_shell_env
    # Preguntar Timeshift al final del express
    step_timeshift
    step_finish
}

# ─────────────────────────── Lista de paquetes ───────────────────────────

show_package_list() {
    local LIST="Paquetes disponibles en este instalador:\n\n"

    LIST+="-- BASE (obligatorios) --\n"
    for p in "${BASE_PACKAGES[@]}"; do LIST+="  $p\n"; done

    LIST+="\n-- XINPUT / ENTRADA --\n"
    local i=0
    while [ $i -lt ${#XINPUT_OPTS[@]} ]; do
        LIST+="  ${XINPUT_OPTS[$i]}  ->  ${XINPUT_OPTS[$((i+1))]}\n"
        i=$((i+3))
    done

    LIST+="\n-- AUDIO --\n"
    i=0
    while [ $i -lt ${#AUDIO_OPTS[@]} ]; do
        LIST+="  ${AUDIO_OPTS[$i]}  ->  ${AUDIO_OPTS[$((i+1))]}\n"
        i=$((i+3))
    done

    LIST+="\n-- KDE PLASMA NUCLEO --\n"
    i=0
    while [ $i -lt ${#PLASMA_CORE_OPTS[@]} ]; do
        LIST+="  ${PLASMA_CORE_OPTS[$i]}  ->  ${PLASMA_CORE_OPTS[$((i+1))]}\n"
        i=$((i+3))
    done

    LIST+="\n-- APLICACIONES KDE --\n"
    i=0
    while [ $i -lt ${#PLASMA_APPS_OPTS[@]} ]; do
        LIST+="  ${PLASMA_APPS_OPTS[$i]}  ->  ${PLASMA_APPS_OPTS[$((i+1))]}\n"
        i=$((i+3))
    done

    LIST+="\n-- ENERGIA (TLP) --\n"
    i=0
    while [ $i -lt ${#TLP_OPTS[@]} ]; do
        LIST+="  ${TLP_OPTS[$i]}  ->  ${TLP_OPTS[$((i+1))]}\n"
        i=$((i+3))
    done

    LIST+="\n-- TIMESHIFT --\n"
    LIST+="  timeshift  ->  Instantaneas rsync o BTRFS del sistema\n"
    LIST+="  snapper    ->  Alternativa BTRFS nativa\n"

    whiptail --title "Lista de Paquetes" --backtitle "$BACKTITLE" \
        --scrolltext --msgbox "$LIST" $HEIGHT $WIDTH
}

# ─────────────────────────── Menu principal ──────────────────────────────

main_menu() {
    while true; do
        CHOICE=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
            --menu "\nElige el modo de instalacion:" \
            $HEIGHT $WIDTH $MENU_HEIGHT \
            "1" "Instalacion Express  (KDE completo, recomendado)" \
            "2" "Instalacion Paso a Paso  (control total)" \
            "3" "Solo ver paquetes disponibles" \
            "x" "Salir" \
            3>&1 1>&2 2>&3) || { log "Saliendo..."; exit 0; }

        case "$CHOICE" in
            1)
                if yesno "Modo Express instalara:\n\n  xorg + xinit + xinput + libinput\n  Microcódigo CPU (AMD/Intel auto-detectado)\n  PipeWire (audio)\n  KDE Plasma 6 + apps esenciales\n  TLP (ahorro de energia)\n  SDDM (gestor de sesion)\n\nDeseas continuar?"; then
                    detect_hardware
                    step_update
                    step_repos
                    install_express
                fi
                ;;
            2)
                step_update
                step_repos
                step_hardware
                step_gpu
                step_base
                step_xinput
                step_audio
                step_plasma_core
                step_plasma_apps
                step_plasma_optional
                step_power
                step_timeshift
                step_pim
                step_extra
                step_shell_env
                step_finish
                ;;
            3)
                show_package_list
                ;;
            x|*)
                log "Saliendo del instalador."
                exit 0
                ;;
        esac
    done
}

# ─────────────────────────── Punto de entrada ────────────────────────────

main() {
    log "========== KDE Plasma Installer iniciado =========="
    check_dependencies
    check_root
    check_void_linux
    step_welcome
    main_menu
}

main
