# KDE Plasma Installer para Void Linux

Instalador interactivo con TUI (interfaz de texto) para instalar **KDE Plasma 6** en **Void Linux**.

```
╔══════════════════════════════════════════════════════╗
║         KDE Plasma Installer — Void Linux            ║
╚══════════════════════════════════════════════════════╝

  1  🚀  Instalación Express (KDE completo recomendado)
  2  🔧  Instalación Paso a Paso (control total)
  3  📋  Solo ver paquetes disponibles
  x  ✖   Salir
```

---

## Instalación rápida (una línea)

```bash
bash <(curl -sL https://raw.githubusercontent.com/TU_USUARIO/kde-void-installer/main/bootstrap.sh)
```

---

## Instalación manual

### 1. Instala las dependencias

```bash
sudo xbps-install -Su git newt
```

### 2. Clona el repositorio

```bash
git clone https://github.com/TU_USUARIO/kde-void-installer.git
cd kde-void-installer
```

### 3. Ejecuta el instalador

```bash
chmod +x install-kde.sh
./install-kde.sh
```

---

## Modos de instalación

### 🚀 Express
Instala todo lo recomendado en un solo paso con barra de progreso:
- xorg + wayland + dbus + NetworkManager
- PipeWire (audio completo)
- KDE Plasma 6 completo
- Aplicaciones esenciales: Dolphin, Gwenview, Spectacle, Ark, KDE Connect, Kcalc
- SDDM (gestor de inicio de sesión)

### 🔧 Paso a paso
Control total sobre qué instalar:

| Paso | Contenido |
|------|-----------|
| 1 | Actualización del sistema |
| 2 | Repositorios (nonfree, multilib, Flathub) |
| 3 | Paquetes base (xorg, wayland, dbus, NetworkManager) |
| 4 | Audio (PipeWire / ALSA) |
| 5 | KDE Plasma núcleo + SDDM |
| 6 | Aplicaciones KDE |
| 7 | Herramientas opcionales |
| 8 | KDE PIM (correo, calendario) |
| 9 | Extras |

---

## Paquetes incluidos

<details>
<summary>Base (siempre instalados)</summary>

- `xorg` — Servidor gráfico X11
- `wayland` — Protocolo gráfico moderno
- `dbus` — Bus de mensajes del sistema
- `NetworkManager` — Gestión de red

</details>

<details>
<summary>Audio</summary>

- `pipewire` + `pipewire-pulse` + `wireplumber` — Stack de audio moderno (recomendado)
- `alsa-utils` — Mezclador de audio
- `pavucontrol` — Control de volumen gráfico

</details>

<details>
<summary>KDE Plasma núcleo</summary>

- `kde-plasma` — Meta paquete principal
- `kde-baseapps` — Kate, Konsole, Khelpcenter
- `plasma-integration` — Integración de tema
- `plasma-wayland-protocols` — Soporte Wayland
- `xdg-desktop-portal-kde` — Portal de escritorio Qt/KF6
- `kwalletmanager` — Monedero de contraseñas
- `breeze` — Tema visual predeterminado
- `sddm` — Gestor de inicio de sesión

</details>

<details>
<summary>Aplicaciones KDE</summary>

- `spectacle` — Capturas de pantalla
- `ark` — Archivador
- `dolphin` — Gestor de archivos
- `gwenview` — Visor de imágenes
- `okular` — Lector PDF
- `kdeconnect` — Sincronización con el móvil
- `kcalc` — Calculadora científica
- `discover` — Tienda de software
- `octoxbps` — Frontend XBPS gráfico
- Y más...

</details>

<details>
<summary>Herramientas opcionales</summary>

- `kio-gdrive` — Google Drive en Dolphin
- `ufw` + `plasma-firewall` — Cortafuegos gráfico
- `flatpak-kcm` — Permisos Flatpak en KDE
- `fwupd` — Actualizaciones de firmware
- `kdegraphics-thumbnailers` — Miniaturas gráficas
- `ffmpegthumbs` — Miniaturas de video

</details>

<details>
<summary>KDE PIM (opcional)</summary>

- `korganizer` — Calendario
- `kontact` — Suite PIM completa
- `akonadi-*` — Backend de datos

</details>

---

## Requisitos previos

- Void Linux instalado (glibc recomendado para soporte Nvidia/Broadcom)
- Conexión a internet
- Usuario con permisos sudo

---

## Después de instalar

1. **Reinicia** el sistema
2. **SDDM** aparecerá como pantalla de inicio de sesión
3. Selecciona **"Plasma (Wayland)"** o **"Plasma (X11)"** en el menú de sesión
4. ¡Listo! KDE Plasma estará configurado

---

## Opciones del script

```
./install-kde.sh         # Ejecución normal
./install-kde.sh -d      # Sin registro (log deshabilitado)
./install-kde.sh -h      # Ayuda
```

El log se guarda en: `~/.local/state/kde-void-installer/install.log`

---

## Basado en

- [Voidlinux-Post-Install-TUI](https://github.com/squidnose/Voidlinux-Post-Install-TUI) por squidnose
- [Linux Bulk App Chooser (LBAC)](https://codeberg.org/squidnose-code/Linux-Bulk-App-Chooser)

---

## Licencia

BSD 2-Clause License — ver [LICENSE](LICENSE)
