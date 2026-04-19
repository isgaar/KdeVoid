#!/bin/bash
# ============================================================
#  KDE Plasma Installer for Void Linux
#  Instalador interactivo de KDE Plasma para Void Linux
# ============================================================
#  Basado en LBAC (Linux Bulk App Chooser)
#  https://codeberg.org/squidnose-code/Linux-Bulk-App-Chooser
# ============================================================

set -euo pipefail

# ─────────────────────────── Colores y estilos ───────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─────────────────────────── Configuración ───────────────────────────────
TITLE="KDE Plasma Installer — Void Linux"
BACKTITLE="KDE Plasma para Void Linux | github.com/tu-usuario/kde-void-installer"
LOGFILE_DIR="$HOME/.local/state/kde-void-installer"
LOGFILE="$LOGFILE_DIR/install.log"
LOGGING=1

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
        *) echo "Opción inválida: -$OPTARG" >&2; exit 1 ;;
    esac
done

# ─────────────────────────── Logging ─────────────────────────────────────
if [ "$LOGGING" -eq 1 ]; then
    mkdir -p "$LOGFILE_DIR"
fi

log() {
    local msg="$*"
    echo -e "$msg"
    if [ "$LOGGING" -eq 1 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$LOGFILE"
    fi
}

# ─────────────────────────── Verificaciones previas ──────────────────────
check_dependencies() {
    local missing=()
    for dep in whiptail xbps-install; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Error: Faltan dependencias: ${missing[*]}${RESET}"
        echo "Instala con: sudo xbps-install -Su newt"
        exit 1
    fi
}

check_void_linux() {
    if [ ! -f /etc/void-release ]; then
        whiptail --title "Advertencia" --yesno \
            "Este script está diseñado para Void Linux.\nParece que estás usando otro sistema.\n\n¿Deseas continuar de todos modos?" \
            10 60 || exit 0
    fi
}

check_root() {
    if [ "$EUID" -eq 0 ]; then
        whiptail --title "Advertencia" --msgbox \
            "No ejecutes este script como root.\nSe pedirá sudo cuando sea necesario." \
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

# Paquetes base obligatorios (siempre instalados)
BASE_PACKAGES=(
    xorg
    wayland
    dbus
    NetworkManager
)

# Grupos de paquetes opcionales
PLASMA_CORE_OPTS=(
    "kde-plasma"                   "Meta paquete KDE Plasma (escritorio completo)" ON
    "kde-baseapps"                 "Kate, Konsole, Khelpcenter" ON
    "plasma-integration"           "Plugins de integración de tema para Plasma" ON
    "plasma-browser-integration"   "Integración del navegador con Plasma 6" OFF
    "plasma-wayland-protocols"     "Protocolos Wayland específicos de Plasma" ON
    "xdg-desktop-portal-kde"       "Backend xdg-desktop-portal para Qt/KF6" ON
    "kwalletmanager"               "Administrador del monedero KDE" OFF
    "breeze"                       "Estilo visual Breeze para Plasma" ON
    "sddm"                         "Gestor de inicio de sesión recomendado para KDE" ON
)

PLASMA_APPS_OPTS=(
    "spectacle"                    "Captura de pantalla de KDE" ON
    "ark"                          "Archivador de KDE" ON
    "7zip-unrar"                   "Soporte RAR para Ark" OFF
    "dolphin"                      "Gestor de archivos Dolphin" ON
    "kolourpaint"                  "Editor de imágenes simple para KDE" OFF
    "krename"                      "Renombrador de archivos en lote para KDE" OFF
    "filelight"                    "Visualizador de uso de disco" OFF
    "kdeconnect"                   "Conecta tu teléfono con el escritorio" ON
    "kcalc"                        "Calculadora científica de KDE" ON
    "discover"                     "Gestor de software (Flatpak y más)" OFF
    "octoxbps"                     "Frontend gráfico para XBPS (Void)" OFF
    "gwenview"                     "Visor de imágenes de KDE" ON
    "okular"                       "Lector de PDF y documentos de KDE" OFF
    "elisa"                        "Reproductor de música de KDE" OFF
    "dragon"                       "Reproductor de video simple de KDE" OFF
)

PLASMA_OPTIONAL_OPTS=(
    "kio-gdrive"                   "Acceso a Google Drive desde Dolphin" OFF
    "kio-extras"                   "Componentes KIO adicionales" OFF
    "ufw"                          "Firewall sin complicaciones (UFW)" OFF
    "plasma-firewall"              "Panel de control para UFW en Plasma" OFF
    "flatpak-kcm"                  "Módulo KDE para permisos Flatpak" OFF
    "fwupd"                        "Actualizaciones de firmware" OFF
    "clinfo"                       "Información OpenCL del sistema" OFF
    "aha"                          "Conversor de color ANSI a HTML (Centro de info)" OFF
    "wayland-utils"                "Utilidades Wayland" OFF
    "kdegraphics-thumbnailers"     "Miniaturas de gráficos en Dolphin" ON
    "ffmpegthumbs"                 "Miniaturas de video en Dolphin" ON
    "ksystemlog"                   "Visor de logs del sistema" OFF
)

PLASMA_PIM_OPTS=(
    "korganizer"                   "Calendario y planificador KDE" OFF
    "kontact"                      "Gestor de información personal KDE" OFF
    "calendarsupport"              "Librería de soporte de calendario" OFF
    "kdepim-addons"                "Addons para aplicaciones KDE PIM" OFF
    "kdepim-runtime"               "Runtime de KDE PIM" OFF
    "akonadi-calendar"             "Integración de calendario con Akonadi" OFF
    "akonadi-contacts"             "Gestión de contactos con Akonadi" OFF
    "akonadi-import-wizard"        "Importar correo desde otros clientes" OFF
)

AUDIO_OPTS=(
    "pipewire"                     "Servidor de audio PipeWire (recomendado)" ON
    "pipewire-pulse"               "Compatibilidad PulseAudio para PipeWire" ON
    "wireplumber"                  "Gestor de sesiones para PipeWire" ON
    "alsa-utils"                   "Utilidades ALSA (mezclador de audio)" ON
    "pavucontrol"                  "Control de volumen gráfico" ON
    "pavucontrol-qt"               "Control de volumen gráfico (Qt)" OFF
)

PYTHON_OPTS=(
    "python3-dbus"                 "Dependencia Python para Eduroam WiFi" OFF
)

# ─────────────────────────── Funciones de menú ───────────────────────────

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

infobox() {
    whiptail --title "$TITLE" --backtitle "$BACKTITLE" --infobox "$1" 8 60
}

progress_bar() {
    local msg="$1"
    local pct="$2"
    echo "$pct"
}

# ─────────────────────────── Instalación con progreso ────────────────────

install_packages() {
    local packages=("$@")
    if [ ${#packages[@]} -eq 0 ]; then
        log "  → Sin paquetes para instalar en este grupo"
        return 0
    fi
    log "  → Instalando: ${packages[*]}"
    sudo xbps-install -Su "${packages[@]}"
}

enable_service() {
    local svc="$1"
    if [ ! -e "/var/service/$svc" ]; then
        sudo ln -sf "/etc/sv/$svc" /var/service/
        log "  → Servicio habilitado: $svc"
    else
        log "  → Servicio ya activo: $svc"
    fi
}

# ─────────────────────────── Pasos de instalación ────────────────────────

step_welcome() {
    whiptail --title "$TITLE" --backtitle "$BACKTITLE" --msgbox \
"╔══════════════════════════════════════════════════════╗
║         KDE Plasma Installer para Void Linux         ║
╚══════════════════════════════════════════════════════╝

Bienvenido, $USER.

Este instalador te guiará paso a paso para instalar
KDE Plasma en tu sistema Void Linux.

Podrás elegir exactamente qué componentes instalar.

Presiona ENTER para continuar." \
    18 60
}

step_update() {
    if yesno "¿Actualizar el sistema antes de instalar?\n\nSe ejecutará: sudo xbps-install -Su\n\n(Muy recomendado para evitar conflictos)"; then
        clear
        log "Actualizando sistema..."
        sudo xbps-install -Su
        msgbox "✓ Sistema actualizado correctamente."
    else
        log "Actualización omitida por el usuario."
    fi
}

step_repos() {
    if yesno "¿Habilitar repositorios adicionales?\n\n• void-repo-nonfree   → Necesario para Nvidia, Broadcom\n• void-repo-multilib  → Necesario para Steam, apps 32-bit\n• Flathub             → Tienda de aplicaciones universal\n\n¿Deseas habilitarlos?"; then
        clear
        log "Habilitando repositorios adicionales..."
        sudo xbps-install -Su void-repo-nonfree void-repo-multilib
        # Flathub
        if command -v flatpak &>/dev/null; then
            flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
            log "  → Flathub agregado"
        else
            log "  → flatpak no instalado, omitiendo Flathub"
        fi
        sudo xbps-install -Su
        msgbox "✓ Repositorios habilitados."
    fi
}

step_base() {
    msgbox "Se instalarán los paquetes base necesarios:\n\n• xorg\n• wayland\n• dbus\n• NetworkManager\n\nEstos son obligatorios para KDE Plasma."
    clear
    log "Instalando paquetes base..."
    install_packages "${BASE_PACKAGES[@]}"
    # Habilitar servicios base
    enable_service dbus
    enable_service NetworkManager
    msgbox "✓ Paquetes base instalados."
}

step_audio() {
    RAW=$(checklist_menu \
        "Audio — $TITLE" \
        "Selecciona los componentes de audio a instalar.\nPipeWire es la opción recomendada para KDE Plasma:" \
        "${AUDIO_OPTS[@]}") || return 0

    RAW=${RAW//\"/}
    read -r -a SELECTED <<< "$RAW"

    if [ ${#SELECTED[@]} -gt 0 ]; then
        clear
        log "Instalando audio: ${SELECTED[*]}"
        install_packages "${SELECTED[@]}"

        # Autostart de PipeWire si se seleccionó
        if [[ " ${SELECTED[*]} " == *" pipewire "* ]]; then
            mkdir -p "$HOME/.config/autostart"
            # Crear autostart para pipewire
            if [ ! -f "$HOME/.config/autostart/pipewire.desktop" ]; then
                cat > "$HOME/.config/autostart/pipewire.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=PipeWire
Exec=pipewire
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
            fi
            log "  → PipeWire configurado para autostart"
        fi
        msgbox "✓ Audio instalado correctamente."
    fi
}

step_plasma_core() {
    RAW=$(checklist_menu \
        "KDE Plasma — Núcleo" \
        "Selecciona los componentes principales de KDE Plasma 6:" \
        "${PLASMA_CORE_OPTS[@]}") || return 0

    RAW=${RAW//\"/}
    read -r -a SELECTED <<< "$RAW"

    if [ ${#SELECTED[@]} -gt 0 ]; then
        clear
        log "Instalando KDE Plasma núcleo: ${SELECTED[*]}"
        install_packages "${SELECTED[@]}"

        # Configurar SDDM si se seleccionó
        if [[ " ${SELECTED[*]} " == *" sddm "* ]]; then
            enable_service sddm
            log "  → SDDM habilitado como gestor de inicio de sesión"
        fi
        msgbox "✓ KDE Plasma instalado correctamente."
    fi
}

step_plasma_apps() {
    RAW=$(checklist_menu \
        "Aplicaciones KDE" \
        "Selecciona las aplicaciones KDE que deseas instalar:" \
        "${PLASMA_APPS_OPTS[@]}") || return 0

    RAW=${RAW//\"/}
    read -r -a SELECTED <<< "$RAW"

    if [ ${#SELECTED[@]} -gt 0 ]; then
        clear
        log "Instalando aplicaciones KDE: ${SELECTED[*]}"
        install_packages "${SELECTED[@]}"
        msgbox "✓ Aplicaciones KDE instaladas."
    fi
}

step_plasma_optional() {
    RAW=$(checklist_menu \
        "Herramientas Opcionales para Plasma" \
        "Utilidades y complementos opcionales para KDE Plasma:" \
        "${PLASMA_OPTIONAL_OPTS[@]}") || return 0

    RAW=${RAW//\"/}
    read -r -a SELECTED <<< "$RAW"

    if [ ${#SELECTED[@]} -gt 0 ]; then
        clear
        log "Instalando herramientas opcionales: ${SELECTED[*]}"
        install_packages "${SELECTED[@]}"

        # Habilitar UFW si se seleccionó
        if [[ " ${SELECTED[*]} " == *" ufw "* ]]; then
            sudo ufw enable 2>/dev/null || true
            enable_service ufw 2>/dev/null || true
            log "  → UFW habilitado"
        fi
        msgbox "✓ Herramientas opcionales instaladas."
    fi
}

step_pim() {
    if yesno "¿Deseas instalar herramientas PIM de KDE?\n\n(Correo, calendario, contactos con Kontact/Akonadi)\n\nSon opcionales y tienen muchas dependencias."; then
        RAW=$(checklist_menu \
            "KDE PIM — Información Personal" \
            "Selecciona los componentes PIM de KDE:" \
            "${PLASMA_PIM_OPTS[@]}") || return 0

        RAW=${RAW//\"/}
        read -r -a SELECTED <<< "$RAW"

        if [ ${#SELECTED[@]} -gt 0 ]; then
            clear
            log "Instalando KDE PIM: ${SELECTED[*]}"
            install_packages "${SELECTED[@]}"
            msgbox "✓ Componentes PIM instalados."
        fi
    fi
}

step_extra() {
    RAW=$(checklist_menu \
        "Extras" \
        "Dependencias adicionales opcionales:" \
        "${PYTHON_OPTS[@]}") || return 0

    RAW=${RAW//\"/}
    read -r -a SELECTED <<< "$RAW"

    if [ ${#SELECTED[@]} -gt 0 ]; then
        clear
        log "Instalando extras: ${SELECTED[*]}"
        install_packages "${SELECTED[@]}"
        msgbox "✓ Extras instalados."
    fi
}

step_finish() {
    local reboot_msg=""
    if yesno "✓ ¡Instalación completada!\n\nSe recomienda reiniciar el sistema para aplicar todos los cambios.\n\n¿Deseas reiniciar ahora?"; then
        log "Usuario eligió reiniciar."
        sudo reboot
    else
        msgbox "Puedes reiniciar más tarde con: sudo reboot\n\nLog guardado en:\n$LOGFILE"
    fi
}

# ─────────────────────────── Modo Express ────────────────────────────────

install_express() {
    log "=== MODO EXPRESS: Instalación completa de KDE Plasma ==="

    local EXPRESS_PACKAGES=(
        xorg wayland dbus NetworkManager
        pipewire pipewire-pulse wireplumber alsa-utils pavucontrol
        kde-plasma kde-baseapps plasma-integration
        plasma-wayland-protocols xdg-desktop-portal-kde
        kwalletmanager breeze sddm
        spectacle ark dolphin gwenview kdeconnect kcalc
        kdegraphics-thumbnailers ffmpegthumbs
    )

    {
        echo 10; sleep 0.3
        echo "# Actualizando sistema..."
        sudo xbps-install -Su 2>/dev/null
        echo 25
        echo "# Instalando paquetes base y audio..."
        sudo xbps-install -Su "${BASE_PACKAGES[@]}" pipewire pipewire-pulse wireplumber alsa-utils pavucontrol 2>/dev/null
        echo 50
        echo "# Instalando KDE Plasma..."
        sudo xbps-install -Su kde-plasma kde-baseapps plasma-integration plasma-wayland-protocols xdg-desktop-portal-kde kwalletmanager breeze sddm 2>/dev/null
        echo 75
        echo "# Instalando aplicaciones KDE..."
        sudo xbps-install -Su spectacle ark dolphin gwenview kdeconnect kcalc kdegraphics-thumbnailers ffmpegthumbs 2>/dev/null
        echo 90
        echo "# Habilitando servicios..."
        enable_service dbus
        enable_service NetworkManager
        enable_service sddm
        echo 100
    } | whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
        --gauge "Instalando KDE Plasma completo..." 8 70 0

    log "=== Modo Express completado ==="
    step_finish
}

# ─────────────────────────── Menú principal ──────────────────────────────

main_menu() {
    while true; do
        CHOICE=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
            --menu "\nElige el modo de instalación:" \
            $HEIGHT $WIDTH $MENU_HEIGHT \
            "1" "🚀  Instalación Express (KDE completo recomendado)" \
            "2" "🔧  Instalación Paso a Paso (control total)" \
            "3" "📋  Solo ver paquetes disponibles" \
            "x" "✖   Salir" \
            3>&1 1>&2 2>&3) || { log "Saliendo..."; exit 0; }

        case "$CHOICE" in
            1)
                if yesno "Modo Express instalará KDE Plasma completo con los paquetes recomendados.\n\n¿Deseas continuar?"; then
                    step_update
                    step_repos
                    install_express
                fi
                ;;
            2)
                # Instalación guiada paso a paso
                step_update
                step_repos
                step_base
                step_audio
                step_plasma_core
                step_plasma_apps
                step_plasma_optional
                step_pim
                step_extra
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

show_package_list() {
    local LIST="Paquetes disponibles en este instalador:\n\n"
    LIST+="── BASE (siempre instalados) ──\n"
    for p in "${BASE_PACKAGES[@]}"; do LIST+="  • $p\n"; done

    LIST+="\n── AUDIO ──\n"
    local i=0
    while [ $i -lt ${#AUDIO_OPTS[@]} ]; do
        LIST+="  • ${AUDIO_OPTS[$i]}  —  ${AUDIO_OPTS[$((i+1))]}\n"
        i=$((i+3))
    done

    LIST+="\n── KDE PLASMA NÚCLEO ──\n"
    i=0
    while [ $i -lt ${#PLASMA_CORE_OPTS[@]} ]; do
        LIST+="  • ${PLASMA_CORE_OPTS[$i]}  —  ${PLASMA_CORE_OPTS[$((i+1))]}\n"
        i=$((i+3))
    done

    LIST+="\n── APLICACIONES KDE ──\n"
    i=0
    while [ $i -lt ${#PLASMA_APPS_OPTS[@]} ]; do
        LIST+="  • ${PLASMA_APPS_OPTS[$i]}  —  ${PLASMA_APPS_OPTS[$((i+1))]}\n"
        i=$((i+3))
    done

    whiptail --title "Lista de Paquetes — $TITLE" --backtitle "$BACKTITLE" \
        --scrolltext --msgbox "$LIST" $HEIGHT $WIDTH
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
