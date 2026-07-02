# Tareas pendientes — requieren Archfrican instalado

Estas tareas no se pueden completar desde macOS porque dependen del estado real
del sistema (módulos gtklock presentes, protocolos Wayland, PAM, hardware de brillo).
Ejecuta los diagnósticos indicados y aplica los cambios desde el PC con Archfrican.

---

## 1. gtklock — pantalla de bloqueo sin wallpaper

**Síntoma:** `⌘+Shift+L` bloquea la pantalla pero no se ve el wallpaper de fondo.

### Diagnóstico (correr en el PC)
```bash
# 1. Ver qué módulos .so están realmente instalados
ls -1 /usr/lib/gtklock/

# 2. Ver qué wallpaper tiene configurado Archfrican
cat ~/.config/archfrican/wallpaper

# 3. Verificar que el archivo existe
file "$(cat ~/.config/archfrican/wallpaper 2>/dev/null)"

# 4. Ver qué lanza archfrican-lock exactamente
archfrican-lock --help 2>/dev/null || head -30 ~/.local/bin/archfrican-lock
```

### Posibles causas y fixes
| Causa | Fix |
|---|---|
| `~/.config/archfrican/wallpaper` vacío o no existe | `echo /ruta/al/wallpaper.jpg > ~/.config/archfrican/wallpaper` |
| Módulo `gtklock-userinfo-module.so` no instalado | `sudo pacman -S gtklock-userinfo-module gtklock-powerbar-module` |
| Ruta del wallpaper con espacios no escapados | Renombrar el archivo sin espacios |
| gtklock no acepta el flag `-b` de esa versión | `gtklock --help \| grep background` para verificar el flag |

### Fix en el repo (después del diagnóstico)
Editar `home/dot_local/bin/executable_archfrican-lock` para corregir la detección
del wallpaper o la invocación de módulos según lo que muestre el diagnóstico.

---

## 2. Phase 3 — Control Center 2.0

### 2a. swaync — slider de brillo

**Objetivo:** añadir un slider de brillo en el panel de swaync (centro de control).

#### Diagnóstico
```bash
# Ver versión de swaync
swaync --version

# Ver si brightnessctl está instalado y funciona
brightnessctl get && brightnessctl max

# Ver el config actual de swaync
cat ~/.config/swaync/config.json

# Ver los widgets disponibles en esa versión
swaync --help | grep widget
```

#### Implementación (en el repo)
- Añadir `brightnessctl` a `packages/niri-desktop.txt`
- En `templates/swaync.config.json` agregar widget `backlight`:
  ```json
  { "type": "backlight", "label": "Brillo", "icon": "display-brightness-symbolic" }
  ```
- `bin/theme-switch` ya renderiza `~/.config/swaync/config.json` — solo añadir el widget

#### DDC brillo para monitores externos
```bash
# Instalar y probar ddcutil
sudo pacman -S ddcutil
sudo ddcutil detect          # ver monitores detectados
sudo ddcutil getvcp 10       # leer brillo actual (VCP code 10)
sudo ddcutil setvcp 10 70    # poner brillo al 70%

# Ver si ddcutil necesita permisos i2c
sudo usermod -aG i2c "$USER" && newgrp i2c
```
Pendiente: `archfrican-brightness` script que use `brightnessctl` (laptop) +
`ddcutil setvcp 10` (monitores externos) con detección automática.

### 2b. Audio — panel de dispositivos

**Objetivo:** abrir `pavucontrol` o un picker de dispositivos desde la waybar/Walker.

#### Diagnóstico
```bash
pactl list sinks short          # ver sinks de audio
pactl list sources short        # ver fuentes (mic)
command -v pavucontrol          # ¿instalado?
command -v helvum               # ¿patchbay instalado?
```

#### Implementación
- `archfrican-audio` script: abre `pavucontrol` o `helvum` según disponibilidad
- `.desktop` entry para Walker
- Paquetes a añadir si no están: `pavucontrol`, `helvum` (AUR, patchbay visual)

### 2c. WiFi — panel de redes

```bash
command -v nm-connection-editor   # GUI de NetworkManager
command -v nmtui                  # TUI de NetworkManager (siempre instalado con NM)
```

- `archfrican-wifi`: lanza `nm-connection-editor` o `nmtui` en ghostty como fallback
- Añadir `nm-connection-editor` a `packages/niri-desktop.txt` si no está

### 2d. Bluetooth — panel de dispositivos

```bash
command -v blueman-manager    # GUI de Blueman (ya en niri-desktop.txt)
bluetoothctl show             # estado del adaptador
```

- `archfrican-bluetooth`: lanza `blueman-manager`; ya está en las acciones
- Verificar que `blueman` está instalado: `pacman -Q blueman`

---

## 3. archfrican-doctor — check_lock

**Objetivo:** `archfrican-doctor` detecte si el locker tiene PAM configurado y
avise en AMBER si falta.

### Diagnóstico
```bash
# Ver estado actual del health check
archfrican-doctor

# Ver qué comprueba health.sh actualmente en la sección de lock
grep -n 'lock\|gtklock\|swaylock\|pam' ~/.local/share/archfrican/health.sh 2>/dev/null \
  || grep -n 'lock\|pam' "$(readlink -f "$(command -v archfrican-doctor)")/../lib/health.sh"
```

### Implementación (en el repo, archivo `lib/health.sh`)
Añadir al bloque de checks de seguridad:
```bash
# Lock PAM
for _lk in gtklock swaylock; do
    command -v "$_lk" >/dev/null 2>&1 || continue
    _pf="/etc/pam.d/$_lk"
    if [ -s "$_pf" ] && grep -qE '^[[:space:]]*auth' "$_pf"; then
        ok "$_lk PAM presente"
    else
        warn "$_lk instalado pero sin PAM — ejecuta: archfrican-update --converge"
    fi
done
# Idle daemon
pgrep -x swayidle >/dev/null 2>&1 && ok "swayidle corriendo" || warn "swayidle no está corriendo"
```

**Nota:** `lib/health.sh` tenía ediciones WM en curso — verificar antes de tocar
que el archivo no tiene cambios sin commitear (`git diff lib/health.sh`).

---

## 4. FIDO2 en el lock screen

**Objetivo:** si el usuario tiene llave FIDO2 enrollada, que también funcione para
desbloquear la pantalla (gtklock/swaylock), no solo para sudo y login.

### Diagnóstico
```bash
# ¿Tiene llave enrollada?
cat ~/.config/.archfrican-fido2 2>/dev/null && echo "FIDO2 enrollada" || echo "Sin FIDO2"

# Ver qué servicios PAM tienen FIDO2 actualmente
grep -l pam_u2f /etc/pam.d/ 2>/dev/null

# Ver el archivo de servicios en el repo
cat "$(readlink -f "$(command -v archfrican-doctor)")/../lib/fido2.sh" | grep FIDO2_PAM
```

### Implementación (en el repo, archivo `lib/fido2.sh`)
Cambiar:
```bash
FIDO2_PAM_SERVICES="sudo system-local-login sddm"
```
Por:
```bash
FIDO2_PAM_SERVICES="sudo system-local-login sddm gtklock swaylock"
```

**Precaución:** probar primero con `fido2_pam_selfcheck gtklock` antes de habilitar.
Si el selfcheck falla, el backup en `/etc/pam.d/gtklock.archfrican.bak` permite revertir.

---

## Orden sugerido de ejecución

1. **gtklock wallpaper** — diagnóstico rápido, fix en minutos
2. **check_lock doctor** — añadir al health check (no requiere hardware, pero confirmar que health.sh no tiene WIP)
3. **Phase 3a** — swaync brillo (más impacto visual inmediato)
4. **FIDO2-on-lock** — solo si hay llave enrollada
5. **Phase 3b/c/d** — audio/wifi/bluetooth panels
