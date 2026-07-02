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
El script `archfrican-lock` ya maneja correctamente ambas rutas de wallpaper y carga
módulos condicionalmente — no se necesitan cambios de código. El problema es ambiental:
asegurarse de que `~/.config/archfrican/wallpaper` contenga una ruta válida a un archivo
que exista.

---

## 1b. gtklock — avatar card / tarjeta de usuario

**Síntoma:** la pantalla de bloqueo no muestra la foto de usuario ni la tarjeta de
login estilo greeter (no se parece al SDDM de Archfrican).

### Diagnóstico
```bash
# ¿Está instalado el módulo userinfo?
ls /usr/lib/gtklock/userinfo.so 2>/dev/null && echo "OK" || echo "FALTA"

# ¿Existe la imagen de avatar?
ls ~/.face 2>/dev/null && file ~/.face || echo "Sin avatar en ~/.face"

# Ver qué carga archfrican-lock en módulos
grep -A5 'userinfo\|modules' ~/.local/bin/archfrican-lock
```

### Fix
| Causa | Fix |
|---|---|
| `gtklock-userinfo-module.so` no instalado | `sudo pacman -S gtklock-userinfo-module` |
| Avatar no configurado | Copiar imagen a `~/.face` (cuadrada, ≥96×96 px, PNG/JPEG) |
| Módulo instalado pero ruta `.so` distinta | `find /usr/lib -name 'userinfo*.so' 2>/dev/null` |

**Nota:** `archfrican-lock` ya usa `-m userinfo` condicionalmente si el `.so` existe —
no requiere cambios en el repo, solo tener el paquete instalado y `~/.face` presente.

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
#### Script `archfrican-brightness` (nuevo, pendiente)
Interfaz unificada para brillo de laptop y monitores externos:

```
archfrican-brightness up        # +10%
archfrican-brightness down      # -10%
archfrican-brightness set 70    # 70% absoluto
```

Lógica interna:
- Detecta backlight de laptop: `brightnessctl -l | grep -i backlight`
- Detecta monitores externos: `ddcutil detect 2>/dev/null | grep -i "Display"`
- Para laptop: `brightnessctl set <N>%`
- Para externos: `ddcutil setvcp 10 <N>` (VCP code 10 = brillo)
- Muestra notificación: `notify-send -t 1500 "Brillo" "<N>%"`
- Refresha waybar si hay módulo de brillo: `pkill -SIGRTMIN+8 waybar`

Keybinds en `home/dot_config/niri/config.kdl.tmpl`:
```kdl
Mod+BrightnessUp   { spawn "archfrican-brightness" "up"; }
Mod+BrightnessDown { spawn "archfrican-brightness" "down"; }
```
(o las teclas `XF86MonBrightnessUp` / `XF86MonBrightnessDown` sin modificador)

Paquetes a añadir a `packages/niri-desktop.txt` si faltan: `brightnessctl`, `ddcutil`.

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

1. **gtklock wallpaper + avatar card (1 y 1b)** — diagnóstico rápido, fix en minutos
2. **check_lock doctor** — añadir al health check (confirmar que `lib/health.sh` no tiene WIP: `git diff lib/health.sh`)
3. **Phase 3a** — `archfrican-brightness` + swaync brillo (más impacto visual inmediato)
4. **FIDO2-on-lock** — solo si hay llave FIDO2 enrollada (`cat ~/.config/.archfrican-fido2`)
5. **Phase 3b/c/d** — audio/wifi/bluetooth panels

---

## 5. Phase 5 — GTK4/Astal dashboard (diferido)

**Estado:** explícitamente diferido hasta que Phase 3 esté validado en hardware.

**Objetivo:** reemplazar waybar + swaync por un shell GTK4 unificado (barra, launcher,
centro de control en un solo proceso) con animaciones fluidas nativas de GTK.

**Framework candidato: Astal**
- Rust/Lua/JS sobre GTK4, activo, módulos sueltos (no todo-o-nada)
- `astal-bar`, `astal-tray`, `astal-battery`, `astal-network`, etc.

**Por qué no Quickshell (QML):** DankMaterialShell lo usa pero está pre-1.0 y el modelo
QML es "todo-o-nada" — incompatible con la filosofía modular de Archfrican.

**Prerequisitos antes de considerar Phase 5:**
1. Phase 3 Control Center 2.0 validado y estable
2. Astal ≥ 0.2 en AUR / repositorio oficial
3. Decisión sobre lenguaje de scripting (Lua vs JS/TS)

**No hay nada que hacer en el repo hasta que la decisión esté tomada.**
