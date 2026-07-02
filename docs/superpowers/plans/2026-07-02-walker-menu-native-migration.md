# Migrar los 5 menús flagship a elephant-menus nativo (Fase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar a `archfrican-layout`, `archfrican-keys`, `archfrican-actions`, `archfrican-defaults` y `archfrican-setup` una versión nativa en `~/.config/elephant/menus/` (TOML donde el contenido es estático, Lua solo donde hace falta leer estado en vivo), alcanzable por su atajo de niri de siempre y desde el buscador de Walker, cayendo al fuzzel original si Walker/elephant no responden.

**Architecture:** Cada script flagship se convierte en un wrapper de 6 líneas: si `walker`+`elephant` responden, `exec walker -m "menus:<nombre>"`; si no, corre la lógica fuzzel original (intacta, en el mismo archivo). Los archivos de menú viven en `home/dot_config/elephant/menus/`; los que necesitan una ruta absoluta a un script `archfrican-*` (para no depender del PATH restringido de los procesos lanzados por niri/elephant) usan sufijo `.tmpl` con `{{ .chezmoi.homeDir }}`, igual que ya hace `config.kdl.tmpl`. Los archivos Lua resuelven `$HOME` ellos mismos vía `os.getenv("HOME")` en tiempo de ejecución, así que no necesitan `.tmpl`. La lógica de negocio (detección de apps instaladas, instalación, parseo de `config.kdl`) sigue viviendo en bash — Lua solo la invoca vía `io.popen()`, nunca la reimplementa.

**Tech Stack:** bash, TOML (elephant-menus), Lua 5.x (elephant-menus, `dofile()`-based code reuse — no `require`), chezmoi, Walker/elephant (versión instalada: elephant `2.21.0-1`, `menus.so` provider confirmado presente).

## Global Constraints

- Spec de referencia: `docs/superpowers/specs/2026-07-02-walker-menu-integration-design.md`.
- **Depende de que el plan `2026-07-02-walker-menu-retire-duplicates.md` (Fase 1) ya esté aplicado** — Task 4 de este plan lee el contenido YA actualizado de `archfrican-actions` (con `walker -m clipboard/symbols/calc/files/websearch` en vez de los 5 scripts retirados). Si Fase 1 no corrió todavía, ejecutarla primero.
- Ningún commit debe incluir atribución a Claude/IA ni trailer `Co-Authored-By`.
- Cada tarea termina con un commit de checkpoint independiente.
- `fixed_order = true` en todo archivo de menú con orden intencional (Walker ordena alfabético por default).
- Todo archivo de menú nuevo requiere reiniciar `elephant` para que Walker lo detecte (confirmado empíricamente: un archivo nuevo no aparece en `elephant listproviders` hasta reiniciar el proceso). El patrón de reinicio usado en cada tarea:
  ```bash
  pkill -x elephant; sleep 0.5
  setsid -f elephant >/dev/null 2>&1
  sleep 1
  ```
  Esto es seguro y de bajo riesgo (mismo patrón ya probado en la sesión de diseño) — no requiere confirmación del usuario, a diferencia de `chezmoi apply` sobre `config.kdl` (que sí la requiere, ver Task 11).
- Para desplegar un archivo nuevo del repo a su ruta real durante el desarrollo de una tarea, usar `chezmoi apply` **con el path del archivo específico** (ej. `chezmoi -S "$(pwd)/home" apply ~/.config/elephant/menus/layout.toml`) — para archivos NUEVOS esto no pide confirmación interactiva (a diferencia de `config.kdl`, que tiene contenido gestionado en vivo fuera de chezmoi).
- Todas las rutas a scripts `archfrican-*` dentro de archivos TOML/Lua deben ser absolutas (`{{ .chezmoi.homeDir }}/.local/bin/archfrican-X` en TOML vía `.tmpl`, o `os.getenv("HOME") .. "/.local/bin/archfrican-X"` en Lua) — los procesos que lanza niri (y por extensión elephant/Walker) heredan el PATH de la sesión `systemd --user`, que no incluye `~/.local/bin` (ver comentario ya existente en `executable_archfrican-defaults:61-63`).

---

### Task 1: `archfrican-layout` → menú nativo (caso más simple, plantilla de referencia)

**Files:**
- Create: `home/dot_config/elephant/menus/layout.toml`
- Modify: `home/dot_local/bin/executable_archfrican-layout` (todo el archivo)

**Interfaces:**
- Consumes: nada.
- Produces: el patrón de wrapper (`command -v walker && elephant listproviders | grep desktopapplications` → `exec walker -m "menus:X"` → fallback) que las Tareas 2, 4, 8 y 9 replican tal cual.

- [ ] **Step 1: Crear `layout.toml`**

```toml
name = "layout"
name_pretty = "Layout"
icon = "view-grid-symbolic"
fixed_order = true

[[entries]]
text = "Un tercio (1/3)"
actions = { run = "niri msg action set-column-width \"33%\"" }

[[entries]]
text = "Mitad (1/2)"
actions = { run = "niri msg action set-column-width \"50%\"" }

[[entries]]
text = "Dos tercios (2/3)"
actions = { run = "niri msg action set-column-width \"67%\"" }

[[entries]]
text = "Maximizar columna"
actions = { run = "niri msg action maximize-column" }

[[entries]]
text = "Pantalla completa"
actions = { run = "niri msg action fullscreen-window" }

[[entries]]
text = "Consumir ventana en la columna"
actions = { run = "niri msg action consume-window-into-column" }

[[entries]]
text = "Expulsar ventana de la columna"
actions = { run = "niri msg action expel-window-from-column" }
```

No necesita `.tmpl` — no referencia ningún script `archfrican-*`, solo `niri msg action` (ya en el PATH del sistema).

- [ ] **Step 2: Desplegar y reiniciar elephant**

```bash
cd /home/jafricanot/Developer/Archfrican
mkdir -p ~/.config/elephant/menus
git add home/dot_config/elephant/menus/layout.toml   # necesario para que chezmoi lo vea como gestionado
chezmoi -S "$(pwd)/home" apply ~/.config/elephant/menus/layout.toml
pkill -x elephant; sleep 0.5
setsid -f elephant >/dev/null 2>&1
sleep 1
```

- [ ] **Step 3: Verificar el menú vía CLI (sin abrir ventana)**

```bash
elephant listproviders | grep -q "^menus:layout$" && echo "provider registrado" || echo "FALTA — revisar el archivo TOML"
elephant query "menus:layout;;10;false" --json
```
Expected: `provider registrado`, y el JSON con 7 líneas, una por entrada, con `"text"` igual a cada uno de los 7 textos de arriba.

- [ ] **Step 4: Reescribir `archfrican-layout` como wrapper**

Contenido actual (7 líneas de lógica, ya leídas — sin cambios en la parte fuzzel, solo se agrega el chequeo de Walker arriba):
```bash
#!/usr/bin/env bash
# Visual tiling layout picker for niri — a Snap-Layouts-style ramp into the scrolling tiler. Pops a
# menu of common column arrangements and applies the choice to the focused column via niri IPC.
# Teaches niri's model without a manual (the thing that makes raw tiling approachable for newcomers).
set -euo pipefail
command -v niri >/dev/null 2>&1 || exit 1

# Native menu (menus/layout.toml) when Walker/elephant are up; fuzzel fallback below otherwise.
if command -v walker >/dev/null 2>&1 \
   && elephant listproviders 2>/dev/null | grep -q "^desktopapplications$"; then
  exec walker -m "menus:layout"
fi

# ── WM seam (niri): all compositor IPC in this file routes through here — one place to port. docs/WM-INTEGRATION.md
wm_action() { niri msg action "$@"; }
sel="$(printf '%s\n' \
  "Un tercio (1/3)" \
  "Mitad (1/2)" \
  "Dos tercios (2/3)" \
  "Maximizar columna" \
  "Pantalla completa" \
  "Consumir ventana en la columna" \
  "Expulsar ventana de la columna" \
  | fuzzel --dmenu --prompt '  layout  ')" || exit 0
case "$sel" in
  "Un tercio"*)   wm_action set-column-width "33%" ;;
  "Mitad"*)       wm_action set-column-width "50%" ;;
  "Dos tercios"*) wm_action set-column-width "67%" ;;
  "Maximizar"*)   wm_action maximize-column ;;
  "Pantalla"*)    wm_action fullscreen-window ;;
  "Consumir"*)    wm_action consume-window-into-column ;;
  "Expulsar"*)    wm_action expel-window-from-column ;;
esac
```

- [ ] **Step 5: Verificar sintaxis y desplegar**

```bash
bash -n /home/jafricanot/Developer/Archfrican/home/dot_local/bin/executable_archfrican-layout
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" apply ~/.local/bin/archfrican-layout
```
Expected: `bash -n` sin salida.

- [ ] **Step 6: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add home/dot_config/elephant/menus/layout.toml home/dot_local/bin/executable_archfrican-layout
git commit -m "$(cat <<'EOF'
feat(walker): native menus:layout provider, fuzzel kept as fallback

archfrican-layout now opens "walker -m menus:layout" when Walker/elephant
are up, falling back to the original fuzzel picker otherwise. Same
7 entries, same niri IPC actions — this is the reference pattern the
other 4 flagship scripts in this phase follow.
EOF
)"
```

---

### Task 2: `archfrican-keys` → menú Lua nativo (dinámico, reusa el `awk` existente)

**Files:**
- Modify: `home/dot_local/bin/executable_archfrican-keys` (agrega subcomando `__tsv` + wrapper)
- Create: `home/dot_config/elephant/menus/keys.lua`

**Interfaces:**
- Consumes: nada.
- Produces: `archfrican-keys __tsv` imprime `key<TAB>categoría<TAB>descripción` por línea (niri binds) y, tras una línea en blanco, `⌘+letra<TAB>Ctrl+letra` por línea (keyd) — interfaz estable que `keys.lua` consume vía `io.popen`.

- [ ] **Step 1: Agregar el subcomando `__tsv` a `archfrican-keys`**

El `awk` que ya lee `config.kdl`/`keyd` (agregado en la sesión anterior, commit `8994a8c`) se reutiliza para una segunda salida en TSV — misma lógica de detección de categoría/nota, distinto `printf`. Insertar esta función ANTES de `emit()`, dejando `emit()` y la invocación final de `fuzzel` sin tocar:

```bash
tsv() {
  if [ -r "$cfg" ]; then
    awk '
      /^[[:space:]]*\/\/[[:space:]]*nota:/ { next }
      /^[[:space:]]*\/\// && $0 !~ /\{/ {
        h = $0
        sub(/^[[:space:]]*\/\/[[:space:]]*/, "", h)
        pending = h
        next
      }
      /^[[:space:]]*(Mod|Print|XF86)[A-Za-z0-9+]*[[:space:]]*\{/ {
        line = $0
        key = line; sub(/[[:space:]]*\{.*/, "", key); gsub(/^[[:space:]]+/, "", key)
        if (line ~ /\/\//) { desc = line; sub(/.*\/\/[[:space:]]*/, "", desc) }
        else { desc = line; sub(/^[^{]*\{[[:space:]]*/, "", desc); sub(/[[:space:]]*;?[[:space:]]*\}.*/, "", desc) }
        gsub(/Mod/, "⌘", key)
        printf "%s\t%s\t%s\n", key, pending, desc
      }' "$cfg"
  fi
  if [ -r "$keyd" ]; then
    printf '\n'
    awk '
      /^\[.*\]/ { insec = ($0 == "[meta]"); next }
      insec && /^[a-z]+[[:space:]]*=/ {
        gsub(/[[:space:]]/, "")
        n = index($0, "="); k = substr($0, 1, n - 1); v = substr($0, n + 1)
        sub(/^C-/, "", v)
        printf "⌘+%s%s\tCtrl+%s\n", toupper(substr(k, 1, 1)), substr(k, 2), toupper(v)
      }' "$keyd"
  fi
}

if [ "${1:-}" = "__tsv" ]; then
  tsv
  exit 0
fi
```

- [ ] **Step 2: Verificar el TSV directamente**

```bash
bash -n /home/jafricanot/Developer/Archfrican/home/dot_local/bin/executable_archfrican-keys
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" apply ~/.local/bin/archfrican-keys
archfrican-keys __tsv | head -5
archfrican-keys __tsv | tail -5
```
Expected: las primeras líneas muestran `⌘+Return<TAB>Lanzadores y núcleo<TAB>abrir terminal` (formato `key<TAB>categoría<TAB>descripción`); las últimas líneas (sección keyd) muestran pares `⌘+C<TAB>Ctrl+C` sin tercera columna.

- [ ] **Step 3: Crear `keys.lua`**

```lua
Name = "keys"
NamePretty = "Atajos de teclado"
Icon = "input-keyboard"
Cache = true
FixedOrder = true
RefreshOnChange = {
  os.getenv("HOME") .. "/.config/niri/config.kdl",
  "/etc/keyd/default.conf",
}

function GetEntries()
  local entries = {}
  local bin = os.getenv("HOME") .. "/.local/bin/archfrican-keys"
  local handle = io.popen(bin .. " __tsv")
  if not handle then return entries end
  local in_keyd = false
  for line in handle:lines() do
    if line == "" then
      in_keyd = true
    elseif in_keyd then
      local key, ctrl = line:match("^([^\t]*)\t([^\t]*)$")
      if key then
        table.insert(entries, { Text = key, Subtext = "macOS ⌘ (keyd) · " .. ctrl, Value = key })
      end
    else
      local key, cat, desc = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)$")
      if key then
        table.insert(entries, { Text = key, Subtext = cat .. " · " .. desc, Value = key })
      end
    end
  end
  handle:close()
  return entries
end
```

`Cache = true` + `RefreshOnChange` (campo `refresh_on_change` del provider, confirmado en `elephant generate doc menus`) hacen que solo recalcule cuando `config.kdl` o `/etc/keyd/default.conf` cambian de verdad — no en cada consulta.

- [ ] **Step 4: Desplegar y verificar**

```bash
cd /home/jafricanot/Developer/Archfrican
mkdir -p ~/.config/elephant/menus
chezmoi -S "$(pwd)/home" apply ~/.config/elephant/menus/keys.lua
pkill -x elephant; sleep 0.5
setsid -f elephant >/dev/null 2>&1
sleep 1
elephant listproviders | grep -q "^menus:keys$" && echo "provider registrado"
elephant query "menus:keys;;10;false" --json | head -5
elephant query "menus:keys;;200;false" --json | wc -l
```
Expected: `provider registrado`; el conteo de líneas debe ser aproximadamente el mismo total que produce `archfrican-keys __tsv | grep -c .` (todas las líneas no vacías).

- [ ] **Step 5: Agregar el wrapper de Walker a `archfrican-keys`**

Insertar esto ANTES de la definición de `emit()` (y después de las variables `cfg`/`keyd` ya existentes, y después del nuevo bloque `tsv()`/`__tsv` del Step 1):

```bash
if command -v walker >/dev/null 2>&1 \
   && elephant listproviders 2>/dev/null | grep -q "^desktopapplications$"; then
  exec walker -m "menus:keys"
fi
```

- [ ] **Step 6: Verificar sintaxis y desplegar**

```bash
bash -n /home/jafricanot/Developer/Archfrican/home/dot_local/bin/executable_archfrican-keys
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" apply ~/.local/bin/archfrican-keys
```

- [ ] **Step 7: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add home/dot_config/elephant/menus/keys.lua home/dot_local/bin/executable_archfrican-keys
git commit -m "$(cat <<'EOF'
feat(walker): native menus:keys provider backed by the existing awk parser

Adds an __tsv subcommand to archfrican-keys (same awk parsing rules as
the fuzzel emit(), different output shape) and a Lua menu whose
GetEntries() shells out to it — no parsing logic duplicated in Lua.
refresh_on_change + cache keep it from re-parsing on every query.
EOF
)"
```

---

### Task 3: Agregar subcomando `toggle` a los 3 scripts que lo necesitan

**Files:**
- Modify: `home/dot_local/bin/executable_archfrican-auto-appearance:13` (bloque `case`)
- Modify: `home/dot_local/bin/executable_archfrican-blur:66` (bloque `case`)
- Modify: `home/dot_local/bin/executable_archfrican-cohesion:38` (bloque `case`)

**Interfaces:**
- Consumes: nada.
- Produces: `archfrican-auto-appearance toggle`, `archfrican-blur toggle`, `archfrican-cohesion toggle` — cada uno consulta su propio `status` y llama a `on`/`off` según corresponda. La Task 4 (`actions.toml`) depende de este subcomando existiendo, porque una entrada TOML no puede computar "on si off, off si on" por sí sola (es un string fijo).

- [ ] **Step 1: Agregar `toggle)` a `archfrican-auto-appearance` (después de `status)` en el `case`, línea 30)**

Contenido actual:
```bash
  status)
    if systemctl --user is-enabled --quiet darkman.service 2>/dev/null; then echo on; else echo off; fi ;;
  *)
    echo "usage: archfrican-auto-appearance on [<lat> <lng>] | off | status" >&2; exit 1 ;;
esac
```

Nuevo contenido:
```bash
  status)
    if systemctl --user is-enabled --quiet darkman.service 2>/dev/null; then echo on; else echo off; fi ;;
  toggle)
    if [ "$("$0" status)" = on ]; then exec "$0" off; else exec "$0" on; fi ;;
  *)
    echo "usage: archfrican-auto-appearance on [<lat> <lng>] | off | status | toggle" >&2; exit 1 ;;
esac
```

- [ ] **Step 2: Agregar `toggle)` a `archfrican-blur` (después de `status)`, línea 81)**

Contenido actual:
```bash
  status)
    if awk '/BLUR-START/{f=1;next}/BLUR-END/{f=0}f' "$cfg" | grep -qE '^[[:space:]]*background-effect[[:space:]]*\{'; then
      echo on; else echo off; fi ;;
  *)
    echo "usage: archfrican-blur on|off|status" >&2; exit 1 ;;
esac
```

Nuevo contenido:
```bash
  status)
    if awk '/BLUR-START/{f=1;next}/BLUR-END/{f=0}f' "$cfg" | grep -qE '^[[:space:]]*background-effect[[:space:]]*\{'; then
      echo on; else echo off; fi ;;
  toggle)
    if [ "$("$0" status)" = on ]; then exec "$0" off; else exec "$0" on; fi ;;
  *)
    echo "usage: archfrican-blur on|off|status|toggle" >&2; exit 1 ;;
esac
```

- [ ] **Step 3: Agregar `toggle)` a `archfrican-cohesion` (después de `status)`, línea 52)**

Contenido actual:
```bash
  status)
    if [ -e "$FLAG" ]; then echo on; else echo off; fi ;;
  apply)
    [ -e "$FLAG" ] || exit 0             # only act when enabled (theme-switch calls this best-effort)
    apply_vscode ;;
  *)
    echo "usage: archfrican-cohesion on | off | status | apply" >&2; exit 1 ;;
esac
```

Nuevo contenido:
```bash
  status)
    if [ -e "$FLAG" ]; then echo on; else echo off; fi ;;
  apply)
    [ -e "$FLAG" ] || exit 0             # only act when enabled (theme-switch calls this best-effort)
    apply_vscode ;;
  toggle)
    if [ "$("$0" status)" = on ]; then exec "$0" off; else exec "$0" on; fi ;;
  *)
    echo "usage: archfrican-cohesion on | off | status | apply | toggle" >&2; exit 1 ;;
esac
```

- [ ] **Step 4: Verificar sintaxis y comportamiento**

```bash
for s in archfrican-auto-appearance archfrican-blur archfrican-cohesion; do
  bash -n "/home/jafricanot/Developer/Archfrican/home/dot_local/bin/executable_$s"
done
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" apply ~/.local/bin/archfrican-auto-appearance ~/.local/bin/archfrican-blur ~/.local/bin/archfrican-cohesion
before="$(archfrican-cohesion status)"
archfrican-cohesion toggle
after="$(archfrican-cohesion status)"
[ "$before" != "$after" ] && echo "toggle OK: $before -> $after" || echo "FALLÓ: no cambió"
archfrican-cohesion "$before" >/dev/null   # dejarlo como estaba antes de la prueba
```
Expected: `toggle OK: <estado-anterior> -> <estado-nuevo>` (con `archfrican-cohesion` específicamente porque no toca hardware/servicios del sistema, a diferencia de blur que reescribe `config.kdl` — verificarlo solo con cohesion evita reescribir el niri config o tocar `darkman.service` como parte de una prueba automatizada).

- [ ] **Step 5: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add home/dot_local/bin/executable_archfrican-auto-appearance \
        home/dot_local/bin/executable_archfrican-blur \
        home/dot_local/bin/executable_archfrican-cohesion
git commit -m "$(cat <<'EOF'
feat(bin): add a self-contained "toggle" subcommand to 3 on/off scripts

archfrican-auto-appearance/blur/cohesion previously required a caller
to read `status` and pass the flipped value (see archfrican-actions'
toggle() helper). A native TOML menu action can't compute that, so each
script now flips itself: "archfrican-X toggle" reads its own status and
execs on/off accordingly. Matches the pattern archfrican-nightlight
already used.
EOF
)"
```

---

### Task 4: `archfrican-actions` → menú TOML nativo (51 entradas estáticas)

**Files:**
- Create: `home/dot_config/elephant/menus/actions.toml.tmpl`
- Modify: `home/dot_local/bin/executable_archfrican-actions` (agrega wrapper al principio)

**Interfaces:**
- Consumes: el subcomando `toggle` de la Task 3 (entradas 6, 7, 42 más abajo).
- Produces: `menus:actions`, consumido por la Task 9 (`archfrican-setup`'s "Asistente" no lo referencia como submenú — sigue llamando al script `archfrican-setup` completo, así que no hay dependencia real ahí). Las Task 5 referencia dos entradas de este archivo (`submenu = "themes"` y `submenu = "pantallas"`) — se agregan en la Task 5, este archivo las deja como placeholders de submenú válidos (el nombre del submenú no necesita existir todavía para que el TOML sea válido, pero la entrada no funcionará hasta la Task 5).

- [ ] **Step 1: Crear `actions.toml.tmpl` con las 51 entradas**

Basado en el `case "$sel"` actual de `archfrican-actions` (ya actualizado por la Fase 1 — Portapapeles/Emoji/Calculadora/Buscar archivos/Buscar en la web ya apuntan a `walker -m <provider>`, ver `docs/superpowers/plans/2026-07-02-walker-menu-retire-duplicates.md`).

```toml
name = "actions"
name_pretty = "Acciones"
icon = "preferences-system"
fixed_order = true

[[entries]]
text = "Asistente de configuración (todo)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-setup" }

[[entries]]
text = "Cambiar tema…"
submenu = "themes"

[[entries]]
text = "Buscar actualizaciones (archfrican-update)"
terminal = true
actions = { run = "sh -c '{{ .chezmoi.homeDir }}/.local/bin/archfrican-update; printf \"\\n(enter para cerrar) \"; read -r _'" }

[[entries]]
text = "Salud del sistema (archfrican-doctor)"
terminal = true
actions = { run = "sh -c '{{ .chezmoi.homeDir }}/.local/bin/archfrican-doctor; printf \"\\n(enter para cerrar) \"; read -r _'" }

[[entries]]
text = "Apps por defecto (navegador/correo)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-defaults" }

[[entries]]
text = "Auto claro/oscuro (alternar)"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-auto-appearance toggle" }

[[entries]]
text = "Blur frosted-glass (alternar)"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-blur toggle" }

[[entries]]
text = "Pantallas / monitores"
submenu = "pantallas"

[[entries]]
text = "Atajos de teclado"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-keys" }

[[entries]]
text = "Bienvenida / tour"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-welcome --tour" }

[[entries]]
text = "Migrar desde otra máquina…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-migrate" }

[[entries]]
text = "Layout de ventana…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-layout" }

[[entries]]
text = "Abrir una sesión/proyecto…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-session" }

[[entries]]
text = "Modo concentración (alternar)"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-focus" }

[[entries]]
text = "Portapapeles (historial)"
actions = { run = "walker -m clipboard" }

[[entries]]
text = "Emoji / símbolos"
actions = { run = "walker -m symbols" }

[[entries]]
text = "Calculadora"
actions = { run = "walker -m calc" }

[[entries]]
text = "Buscar archivos"
actions = { run = "walker -m files" }

[[entries]]
text = "Buscar en la web"
actions = { run = "walker -m websearch" }

[[entries]]
text = "Navegador (Brave/Vivaldi)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-browser" }

[[entries]]
text = "Tienda de apps (Flatpak)"
actions = { run = "gnome-software" }

[[entries]]
text = "Permisos de apps (Flatseal)"
actions = { run = "flatpak run com.github.tchx84.Flatseal" }

[[entries]]
text = "Crear web-app…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-webapp" }

[[entries]]
text = "Git / repositorios (SSH + GitHub)…"
terminal = true
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-git" }

[[entries]]
text = "Nube / SMB…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-cloud" }

[[entries]]
text = "Centro de control (notificaciones)"
actions = { run = "swaync-client -t -sw" }

[[entries]]
text = "No molestar (alternar)"
actions = { run = "swaync-client -d -sw" }

[[entries]]
text = "Luz nocturna (alternar)"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-nightlight toggle" }

[[entries]]
text = "VPN (Tailscale/WireGuard)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-vpn" }

[[entries]]
text = "Mullvad (VPN + Browser)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-mullvad" }

[[entries]]
text = "Audio: efectos / EQ (EasyEffects)"
actions = { run = "easyeffects" }

[[entries]]
text = "Audio: patchbay (qpwgraph)"
actions = { run = "qpwgraph" }

[[entries]]
text = "Accesibilidad (lector, contraste)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-a11y" }

[[entries]]
text = "Lector de pantalla (alternar)"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-screenreader" }

[[entries]]
text = "Método de entrada / IME (CJK)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-ime" }

[[entries]]
text = "Energía / batería (laptop)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-power" }

[[entries]]
text = "Instalar stack de gaming (Steam)…"
terminal = true
actions = { run = "sh -c '{{ .chezmoi.homeDir }}/.archfrican/install.sh 65-gaming yes; printf \"(enter para cerrar) \"; read -r _'" }

[[entries]]
text = "Continuidad (KDE Connect + LocalSend)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-continuity" }

[[entries]]
text = "Respaldo de ~ (Time Machine)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-backup" }

[[entries]]
text = "Revertir actualización (rollback)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-rollback" }

[[entries]]
text = "Wallpaper / theming dinámico…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-wallpaper" }

[[entries]]
text = "Cohesión de apps (alternar)"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-cohesion toggle" }

[[entries]]
text = "Huella digital para sudo…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-fingerprint" }

[[entries]]
text = "Splash de arranque (Plymouth)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-plymouth" }

[[entries]]
text = "Cámara (ajustes)"
actions = { run = "cameractrls" }

[[entries]]
text = "Auto-unlock por TPM (disco cifrado)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-tpm-unlock" }

[[entries]]
text = "Secure Boot (sbctl)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-secureboot" }

[[entries]]
text = "Privacidad…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-privacy" }

[[entries]]
text = "Bluetooth"
actions = { run = "blueman-manager" }

[[entries]]
text = "Audio (mezclador)"
actions = { run = "pavucontrol" }

[[entries]]
text = "Red / VPN"
actions = { run = "nm-connection-editor" }
```

- [ ] **Step 2: Desplegar y verificar conteo/orden**

```bash
cd /home/jafricanot/Developer/Archfrican
mkdir -p ~/.config/elephant/menus
chezmoi -S "$(pwd)/home" apply ~/.config/elephant/menus/actions.toml
pkill -x elephant; sleep 0.5
setsid -f elephant >/dev/null 2>&1
sleep 1
elephant listproviders | grep -q "^menus:actions$" && echo "provider registrado"
elephant query "menus:actions;;60;false" --json | wc -l
elephant query "menus:actions;;60;false" --json | head -1
```
Expected: `provider registrado`; 51 líneas de salida; la primera entrada es "Asistente de configuración (todo)…" (confirma `fixed_order` funcionando — sin él, Walker las mostraría alfabéticas y "Abrir una sesión…" saldría primero).

- [ ] **Step 3: Agregar el wrapper a `archfrican-actions`**

Insertar al principio del archivo, antes de `sel="$(printf ...`:

```bash
#!/usr/bin/env bash
# archfrican-actions — the command surface / "control center in the launcher".
# One fuzzel menu that reaches every Archfrican action and every launcher mode,
# the way Spotlight Actions / omarchy-menu / a KRunner do. Each item is a named
# verb (same spirit as the bin/ tools), so the keyboard-driven system stays
# discoverable instead of memorized.
set -euo pipefail
B="$HOME/.local/bin"
toggle() { [ "$("$1" status 2>/dev/null)" = on ] && echo off || echo on; }

# Native menu (menus/actions.toml) when Walker/elephant are up; fuzzel fallback below otherwise.
if command -v walker >/dev/null 2>&1 \
   && elephant listproviders 2>/dev/null | grep -q "^desktopapplications$"; then
  exec walker -m "menus:actions"
fi

sel="$(printf '%s\n' \
  ...
```
(el resto del archivo, desde `sel="$(printf...` hasta el final del `case`, queda exactamente igual — no se toca nada más).

- [ ] **Step 4: Verificar sintaxis y desplegar**

```bash
bash -n /home/jafricanot/Developer/Archfrican/home/dot_local/bin/executable_archfrican-actions
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" apply ~/.local/bin/archfrican-actions
```

- [ ] **Step 5: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add home/dot_config/elephant/menus/actions.toml.tmpl home/dot_local/bin/executable_archfrican-actions
git commit -m "$(cat <<'EOF'
feat(walker): native menus:actions provider (51 static entries)

archfrican-actions now opens "walker -m menus:actions" when Walker is
up. Every entry is a fixed text->command mapping, so this stays plain
TOML — no Lua needed here. "Cambiar tema…" and "Pantallas / monitores"
reference submenus (themes, pantallas) added in the next task.
EOF
)"
```

---

### Task 5: Submenú de temas (Lua, dinámico) y submenú de pantallas (TOML, estático y compartido)

**Files:**
- Create: `home/dot_config/elephant/menus/themes.lua`
- Create: `home/dot_config/elephant/menus/pantallas.toml.tmpl`

**Interfaces:**
- Consumes: `submenu = "themes"` y `submenu = "pantallas"`, ya referenciados en `actions.toml.tmpl` (Task 4). La Task 9 (`archfrican-setup`) también referencia ambos — son compartidos, un solo archivo cada uno, no duplicados.
- Produces: `menus:themes` (lista dinámica de `~/.archfrican/themes/*/`) y `menus:pantallas` (2 entradas fijas: Organizar / Guardar).

- [ ] **Step 1: Crear `themes.lua`**

```lua
Name = "themes"
NamePretty = "Temas"
Icon = "preferences-desktop-theme"
Cache = false

function GetEntries()
  local entries = {}
  local dir = os.getenv("HOME") .. "/.archfrican/themes"
  local handle = io.popen("for d in '" .. dir .. "'/*/; do [ -d \"$d\" ] && basename \"$d\"; done 2>/dev/null")
  if not handle then return entries end
  for name in handle:lines() do
    if name ~= "" then
      table.insert(entries, { Text = name, Value = name, Actions = { apply = "theme-switch '%VALUE%'" } })
    end
  end
  handle:close()
  return entries
end
```

`Cache = false` porque el usuario puede instalar/agregar temas nuevos en cualquier momento — se recalcula en cada consulta (a diferencia de `keys.lua`, que usa `refresh_on_change` porque depende de 2 archivos concretos, no de un directorio cuyo contenido cambia sin previo aviso).

- [ ] **Step 2: Crear `pantallas.toml.tmpl`**

Basado en el submenú "Pantallas" idéntico que hoy está duplicado en `archfrican-actions:76-82` y `archfrican-setup:32-38` (esta migración lo deduplica en un solo archivo):

```toml
name = "pantallas"
name_pretty = "Pantallas"
icon = "video-display"
fixed_order = true

[[entries]]
text = "Organizar pantallas (se guarda al cerrar)"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-displays edit" }

[[entries]]
text = "Guardar el layout actual ahora"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-displays save" }
```

- [ ] **Step 3: Desplegar y verificar ambos**

```bash
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" apply ~/.config/elephant/menus/themes.lua ~/.config/elephant/menus/pantallas.toml
pkill -x elephant; sleep 0.5
setsid -f elephant >/dev/null 2>&1
sleep 1
elephant listproviders | grep -E "^menus:(themes|pantallas)$"
elephant query "menus:themes;;10;false" --json
elephant query "menus:pantallas;;10;false" --json
```
Expected: ambos providers listados; `menus:themes` devuelve al menos una entrada por cada subdirectorio real bajo `~/.archfrican/themes/`; `menus:pantallas` devuelve exactamente 2 entradas con el texto de arriba.

- [ ] **Step 4: Confirmar que el submenú se abre desde `actions.toml`**

```bash
elephant query "menus:actions;;60;false" --json | grep -o '"text":"Cambiar tema[^"]*"'
elephant query "menus:actions;;60;false" --json | grep -o '"text":"Pantallas[^"]*"'
```
Expected: ambas líneas aparecen (confirma que las entradas de `actions.toml` con `submenu = "themes"`/`"pantallas"` siguen listadas normalmente — el submenú se activa al seleccionarlas dentro de Walker, no cambia cómo aparecen en la lista padre).

- [ ] **Step 5: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add home/dot_config/elephant/menus/themes.lua home/dot_config/elephant/menus/pantallas.toml.tmpl
git commit -m "$(cat <<'EOF'
feat(walker): themes and pantallas submenus, shared between actions/setup

menus:themes lists ~/.archfrican/themes/*/ live via io.popen (Lua,
since it's genuinely dynamic). menus:pantallas is the static
Organizar/Guardar pair that archfrican-actions and archfrican-setup
both used to duplicate inline — now a single shared TOML file.
EOF
)"
```

---

### Task 6: `archfrican-defaults` — exponer `__list` y `__apply` como subcomandos

**Files:**
- Modify: `home/dot_local/bin/executable_archfrican-defaults` (agrega dispatch de subcomandos, sin tocar `category()`/`is_installed()`/`do_install()`/`apply_default()`/`pkg_installed()`)

**Interfaces:**
- Consumes: nada — reutiliza las funciones ya existentes (`is_installed`, `do_install`, `apply_default`, `pkg_installed`) tal cual están.
- Produces: `archfrican-defaults __list <slug>` imprime `display<TAB>installed(0|1)` por fila de la categoría `<slug>`; `archfrican-defaults __apply <slug> <display>` ejecuta exactamente lo que hoy hace la segunda mitad de `category()` (instalar si falta, aplicar default) para esa fila. Las Tasks 7 y 8 consumen esta interfaz desde Lua vía `io.popen`.

- [ ] **Step 1: Extraer las tablas de categoría a variables reutilizables**

Las 10 tablas ya existen como argumentos posicionales dentro del `case "$cat"` (líneas 129-194). Para que `__list`/`__apply` puedan encontrar la tabla correcta por slug sin duplicar los datos, se factorizan en un `case` propio que devuelve `how`, `targets` y las filas — reemplazar TODO el bloque desde `cat="$(printf ...` (línea 121) hasta el final del archivo (línea 195) por:

```bash
category_data() {   # category_data <slug> ; sets HOW, TARGETS, ROWS (global, for this call only)
  case "$1" in
    browser)
      HOW=browser; TARGETS='x-scheme-handler/http x-scheme-handler/https text/html'
      ROWS=(
        "Firefox|firefox.desktop|repo:firefox"
        "Brave|brave-browser.desktop|aur:brave-bin"
        "Chromium|chromium.desktop|repo:chromium"
        "Vivaldi|vivaldi-stable.desktop|aur:vivaldi"
        "Mullvad Browser|mullvad-browser.desktop|aur:mullvad-browser-bin"
      ) ;;
    editor)
      HOW=mime; TARGETS='text/plain text/markdown application/json text/x-csrc text/x-c++src text/x-python application/x-shellscript text/x-java'
      ROWS=(
        "VS Code (OSS)|code-oss.desktop|repo:code"
        "Zed|dev.zed.Zed.desktop|repo:zed"
        "Neovim (terminal)|nvim.desktop|repo:neovim"
        "Gnome Text Editor|org.gnome.TextEditor.desktop|repo:gnome-text-editor"
        "Kate|org.kde.kate.desktop|repo:kate"
        "Cursor|cursor.desktop|aur:cursor-bin"
        "Antigravity|antigravity-ide.desktop|aur:antigravity-ide"
      ) ;;
    ia-cli)
      HOW=cli; TARGETS=''
      ROWS=(
        "Claude Code|claude|script:https://claude.ai/install.sh"
        "OpenCode|opencode|aur:opencode-bin"
        "Gemini CLI|gemini|aur:gemini-cli-git"
        "Aider|aider|aur:aider-chat"
        "Codex CLI|codex|aur:openai-codex-bin"
      ) ;;
    terminal)
      HOW=terminal; TARGETS=''
      ROWS=(
        "Ghostty|com.mitchellh.ghostty.desktop|repo:ghostty"
        "Kitty|kitty.desktop|repo:kitty"
        "Alacritty|Alacritty.desktop|repo:alacritty"
        "foot|foot.desktop|repo:foot"
      ) ;;
    archivos)
      HOW=mime; TARGETS='inode/directory'
      ROWS=(
        "Nautilus (Files)|org.gnome.Nautilus.desktop|repo:nautilus"
        "Dolphin|org.kde.dolphin.desktop|repo:dolphin"
        "Thunar|thunar.desktop|repo:thunar"
        "Nemo|nemo.desktop|repo:nemo"
      ) ;;
    pdf)
      HOW=mime; TARGETS='application/pdf'
      ROWS=(
        "Papers / Evince|org.gnome.Evince.desktop|repo:evince"
        "Okular|org.kde.okular.desktop|repo:okular"
        "Zathura|org.pwmt.zathura.desktop|repo:zathura zathura-pdf-mupdf"
      ) ;;
    imagenes)
      HOW=mime; TARGETS='image/png image/jpeg image/gif image/webp image/svg+xml image/tiff image/bmp'
      ROWS=(
        "Loupe|org.gnome.Loupe.desktop|repo:loupe"
        "Image Viewer (eog)|org.gnome.eog.desktop|repo:eog"
        "gThumb|org.gnome.gThumb.desktop|repo:gthumb"
        "imv|imv.desktop|repo:imv"
      ) ;;
    correo)
      HOW=mime; TARGETS='x-scheme-handler/mailto'
      ROWS=(
        "Thunderbird|thunderbird.desktop|repo:thunderbird"
        "Geary|org.gnome.Geary.desktop|repo:geary"
        "Evolution|org.gnome.Evolution.desktop|repo:evolution"
      ) ;;
    contenedores)
      HOW=cli; TARGETS=''
      ROWS=(
        "LazyDocker|lazydocker|repo:lazydocker"
        "Docker Desktop|docker-desktop.desktop|aur-warn:docker-desktop|none"
      ) ;;
    mensajeria)
      HOW=none; TARGETS=''
      ROWS=(
        "Telegram|org.telegram.desktop.desktop|flatpak:org.telegram.desktop"
        "Signal|org.signal.Signal.desktop|flatpak:org.signal.Signal"
        "Discord|com.discordapp.Discord.desktop|flatpak:com.discordapp.Discord"
        "WhatsApp (web app)|archfrican-webapp-whatsapp.desktop|webapp:WhatsApp,https://web.whatsapp.com"
      ) ;;
    *) return 1 ;;
  esac
}

list_category() {   # list_category <slug> ; TSV: display<TAB>installed(0|1)
  category_data "$1" || return 1
  local row disp id spec row_how
  for row in "${ROWS[@]}"; do
    IFS='|' read -r disp id spec row_how <<<"$row"; row_how="${row_how:-$HOW}"
    if is_installed "$row_how" "$id"; then printf '%s\t1\n' "$disp"; else printf '%s\t0\n' "$disp"; fi
  done
}

apply_category() {   # apply_category <slug> <display> ; same dispatch category()'s second half already did
  category_data "$1" || return 1
  local want="$2" row disp id spec row_how
  local tgt=(); [ -n "$TARGETS" ] && read -r -a tgt <<<"$TARGETS"
  for row in "${ROWS[@]}"; do
    IFS='|' read -r disp id spec row_how <<<"$row"; row_how="${row_how:-$HOW}"
    [ "$disp" = "$want" ] || continue
    if ! is_installed "$row_how" "$id"; then
      do_install "$spec" || return 0
      if ! is_installed "$row_how" "$id" && ! pkg_installed "$spec"; then note "$disp no quedó instalado"; return 0; fi
    fi
    if [ "$row_how" = cli ] || [ "$row_how" = none ]; then note "$disp listo ✓"
    else apply_default "$id" "$row_how" ${tgt[@]+"${tgt[@]}"}; note "Por defecto: $disp"; fi
    return 0
  done
}

CATEGORY_LABELS=(
  "browser|Navegador web" "editor|Editor / IDE" "ia-cli|IA / agentes (CLI)" "terminal|Terminal"
  "archivos|Gestor de archivos" "pdf|Visor de PDF" "imagenes|Visor de imágenes" "correo|Correo"
  "contenedores|Gestor de contenedores" "mensajeria|Mensajería"
)

case "${1:-}" in
  __list)  list_category "$2" ;;
  __apply) apply_category "$2" "$3" ;;
  *)
    cat="$(printf '%s\n' \
      "Navegador web" "Editor / IDE" "IA / agentes (CLI)" "Terminal" "Gestor de archivos" \
      "Visor de PDF" "Visor de imágenes" "Correo" "Gestor de contenedores" "Mensajería" \
      "Control de versiones · Git…" \
      | fuzzel --dmenu --prompt '  app por defecto  ')" || exit 0
    slug=""
    case "$cat" in
      "Control de versiones"*) exec "$HOME/.local/bin/archfrican-git" ;;
      "Navegador web") slug=browser ;;
      "Editor / IDE") slug=editor ;;
      "IA / agentes (CLI)") slug=ia-cli ;;
      "Terminal") slug=terminal ;;
      "Gestor de archivos") slug=archivos ;;
      "Visor de PDF") slug=pdf ;;
      "Visor de imágenes") slug=imagenes ;;
      "Correo") slug=correo ;;
      "Gestor de contenedores") slug=contenedores ;;
      "Mensajería") slug=mensajeria ;;
    esac
    [ -n "$slug" ] || exit 0
    category_data "$slug"
    local_prompt="$(printf '%s\n' "${CATEGORY_LABELS[@]}" | awk -F'|' -v s="$slug" '$1==s{print $2}')"
    entries=(); for row in "${ROWS[@]}"; do
      IFS='|' read -r disp id spec row_how <<<"$row"; row_how="${row_how:-$HOW}"
      if is_installed "$row_how" "$id"; then entries+=("$disp"); else entries+=("⤓ Instalar $disp…"); fi
    done
    [ "$HOW" = cli ] || entries+=("Otra app instalada…")
    sel="$(printf '%s\n' "${entries[@]}" | fuzzel --dmenu --prompt "  $local_prompt  ")" || exit 0
    [ -n "$sel" ] || exit 0
    if [ "$sel" = "Otra app instalada…" ]; then
      id="$(list_apps | fuzzel --dmenu --prompt "  $local_prompt  " | cut -f2)"; [ -n "$id" ] || exit 0
      tgt=(); [ -n "$TARGETS" ] && read -r -a tgt <<<"$TARGETS"
      apply_default "$id" "$HOW" ${tgt[@]+"${tgt[@]}"}; note "Por defecto: $id"; exit 0
    fi
    want="${sel#⤓ Instalar }"; want="${want%…}"
    apply_category "$slug" "$want" ;;
esac
```

Nota: este `case` final reemplaza al `category()` original línea por línea (mismo comportamiento — instala si falta, aplica default, ofrece "Otra app instalada…"), pero ahora construido sobre `category_data`/`list_category`/`apply_category` para que `__list`/`__apply` reutilicen exactamente la misma fuente de datos que la ruta fuzzel. `category()` como función standalone se elimina — sus dos mitades pasan a ser `list_category`/`apply_category`.

- [ ] **Step 2: Verificar sintaxis**

```bash
bash -n /home/jafricanot/Developer/Archfrican/home/dot_local/bin/executable_archfrican-defaults
```
Expected: sin salida.

- [ ] **Step 3: Desplegar y probar `__list`/`__apply` directamente**

```bash
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" apply ~/.local/bin/archfrican-defaults
archfrican-defaults __list browser
archfrican-defaults __list terminal
```
Expected: `__list browser` imprime 5 líneas `Nombre<TAB>0` o `Nombre<TAB>1` según lo que ya esté instalado (ej. si Firefox está instalado, `Firefox<TAB>1`); `__list terminal` imprime 4 líneas, y `Ghostty<TAB>1` porque `ghostty` ya es una dependencia base de este sistema (confirmado por su uso en toda la config de niri).

- [ ] **Step 4: Probar el flujo fuzzel original sigue intacto (regresión manual)**

Esta verificación requiere al usuario presente (abre una ventana real): confirmar que ejecutar `archfrican-defaults` sin argumentos todavía muestra el picker de categorías y, al elegir una app ya instalada, aplica el default sin errores — mismo comportamiento que antes de esta tarea.

- [ ] **Step 5: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add home/dot_local/bin/executable_archfrican-defaults
git commit -m "$(cat <<'EOF'
refactor(defaults): expose __list/__apply subcommands per category

Splits category()'s two halves into list_category()/apply_category(),
addressable by slug via new __list/__apply subcommands, without
changing install-detection or install-execution logic. The interactive
fuzzel flow (no args) behaves identically. This is the bash-side API
the native Lua category menus (next tasks) shell out to.
EOF
)"
```

---

### Task 7: `defaults.toml` (categorías) + helper Lua compartido + primera categoría de prueba

**Files:**
- Create: `home/dot_config/elephant/menus/defaults.toml.tmpl`
- Create: `home/dot_config/elephant/lib/defaults-helpers.lua`
- Create: `home/dot_config/elephant/menus/defaults-browser.lua`

**Interfaces:**
- Consumes: `archfrican-defaults __list <slug>` / `__apply <slug> <display>` (Task 6).
- Produces: `BuildCategoryEntries(slug, prettyName)` en `defaults-helpers.lua`, consumida por `defaults-browser.lua` acá y por las 9 categorías restantes en la Task 8 vía `dofile()`.

- [ ] **Step 1: Crear el helper compartido `defaults-helpers.lua`**

No es un menú (no tiene `Name`/`GetEntries` de nivel raíz que elephant pudiera intentar registrar como provider) — vive fuera de `menus/`, en `lib/`, así elephant no lo escanea al buscar menús.

```lua
function BuildCategoryEntries(slug)
  local entries = {}
  local bin = os.getenv("HOME") .. "/.local/bin/archfrican-defaults"
  local handle = io.popen(bin .. " __list " .. slug)
  if not handle then return entries end
  for line in handle:lines() do
    local disp, installed = line:match("^([^\t]*)\t([01])$")
    if disp then
      local text = disp
      if installed == "0" then text = "⤓ Instalar " .. disp .. "…" end
      table.insert(entries, {
        Text = text,
        Value = disp,
        Actions = { apply = bin .. " __apply " .. slug .. " '%VALUE%'" },
      })
    end
  end
  handle:close()
  return entries
end
```

- [ ] **Step 2: Crear `defaults-browser.lua` (primera categoría, prueba de concepto)**

```lua
Name = "defaults-browser"
NamePretty = "Navegador web"
Icon = "web-browser"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("browser")
end
```

- [ ] **Step 3: Crear `defaults.toml.tmpl` (10 categorías + Git)**

```toml
name = "defaults"
name_pretty = "Apps por defecto"
icon = "preferences-desktop-default-applications"
fixed_order = true

[[entries]]
text = "Navegador web"
submenu = "defaults-browser"

[[entries]]
text = "Editor / IDE"
submenu = "defaults-editor"

[[entries]]
text = "IA / agentes (CLI)"
submenu = "defaults-ia-cli"

[[entries]]
text = "Terminal"
submenu = "defaults-terminal"

[[entries]]
text = "Gestor de archivos"
submenu = "defaults-archivos"

[[entries]]
text = "Visor de PDF"
submenu = "defaults-pdf"

[[entries]]
text = "Visor de imágenes"
submenu = "defaults-imagenes"

[[entries]]
text = "Correo"
submenu = "defaults-correo"

[[entries]]
text = "Gestor de contenedores"
submenu = "defaults-contenedores"

[[entries]]
text = "Mensajería"
submenu = "defaults-mensajeria"

[[entries]]
text = "Control de versiones · Git…"
terminal = true
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-git" }
```

(Las 9 categorías restantes — `defaults-editor`, `defaults-ia-cli`, etc. — se crean en la Task 8; hasta entonces, esas entradas de `defaults.toml` apuntan a submenús que todavía no existen y Walker mostraría un error si se seleccionan. Es seguro dejarlas así entre tareas porque nadie más referencia `defaults.toml` todavía.)

- [ ] **Step 4: Desplegar y probar la categoría de prueba de punta a punta**

```bash
cd /home/jafricanot/Developer/Archfrican
mkdir -p ~/.config/elephant/lib
chezmoi -S "$(pwd)/home" apply \
  ~/.config/elephant/menus/defaults.toml \
  ~/.config/elephant/lib/defaults-helpers.lua \
  ~/.config/elephant/menus/defaults-browser.lua
pkill -x elephant; sleep 0.5
setsid -f elephant >/dev/null 2>&1
sleep 1
elephant listproviders | grep -E "^menus:defaults(-browser)?$"
elephant query "menus:defaults;;15;false" --json | wc -l
elephant query "menus:defaults-browser;;10;false" --json
```
Expected: ambos providers listados; `menus:defaults` devuelve 11 líneas (10 categorías + Git); `menus:defaults-browser` devuelve 5 entradas, cada una con el mismo texto ("Firefox" o "⤓ Instalar Firefox…", etc.) que ya se vio en la Task 6 Step 3 vía `__list browser`.

- [ ] **Step 5: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add home/dot_config/elephant/menus/defaults.toml.tmpl \
        home/dot_config/elephant/lib/defaults-helpers.lua \
        home/dot_config/elephant/menus/defaults-browser.lua
git commit -m "$(cat <<'EOF'
feat(walker): menus:defaults category picker + shared Lua helper + browser

defaults.toml lists the 10 categories (submenu refs) plus the Git
passthrough. defaults-helpers.lua's BuildCategoryEntries(slug) shells
out to archfrican-defaults' new __list/__apply subcommands — no
install-detection logic duplicated in Lua. defaults-browser.lua proves
the pattern end-to-end before applying it to the other 9 categories.
EOF
)"
```

---

### Task 8: Las 9 categorías restantes + wrapper de `archfrican-defaults`

**Files:**
- Create: `home/dot_config/elephant/menus/defaults-editor.lua`
- Create: `home/dot_config/elephant/menus/defaults-ia-cli.lua`
- Create: `home/dot_config/elephant/menus/defaults-terminal.lua`
- Create: `home/dot_config/elephant/menus/defaults-archivos.lua`
- Create: `home/dot_config/elephant/menus/defaults-pdf.lua`
- Create: `home/dot_config/elephant/menus/defaults-imagenes.lua`
- Create: `home/dot_config/elephant/menus/defaults-correo.lua`
- Create: `home/dot_config/elephant/menus/defaults-contenedores.lua`
- Create: `home/dot_config/elephant/menus/defaults-mensajeria.lua`
- Modify: `home/dot_local/bin/executable_archfrican-defaults` (agrega wrapper)

**Interfaces:**
- Consumes: `BuildCategoryEntries` (Task 7), `archfrican-defaults __list/__apply` (Task 6).
- Produces: cierra el árbol de submenús de `defaults.toml` — las 10 categorías quedan todas funcionales.

- [ ] **Step 1: Crear las 9 categorías (mismo patrón que `defaults-browser.lua`, un slug distinto cada una)**

`defaults-editor.lua`:
```lua
Name = "defaults-editor"
NamePretty = "Editor / IDE"
Icon = "accessories-text-editor"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("editor")
end
```

`defaults-ia-cli.lua`:
```lua
Name = "defaults-ia-cli"
NamePretty = "IA / agentes (CLI)"
Icon = "utilities-terminal"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("ia-cli")
end
```

`defaults-terminal.lua`:
```lua
Name = "defaults-terminal"
NamePretty = "Terminal"
Icon = "utilities-terminal"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("terminal")
end
```

`defaults-archivos.lua`:
```lua
Name = "defaults-archivos"
NamePretty = "Gestor de archivos"
Icon = "system-file-manager"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("archivos")
end
```

`defaults-pdf.lua`:
```lua
Name = "defaults-pdf"
NamePretty = "Visor de PDF"
Icon = "application-pdf"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("pdf")
end
```

`defaults-imagenes.lua`:
```lua
Name = "defaults-imagenes"
NamePretty = "Visor de imágenes"
Icon = "image-viewer"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("imagenes")
end
```

`defaults-correo.lua`:
```lua
Name = "defaults-correo"
NamePretty = "Correo"
Icon = "mail-unread"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("correo")
end
```

`defaults-contenedores.lua`:
```lua
Name = "defaults-contenedores"
NamePretty = "Gestor de contenedores"
Icon = "applications-system"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("contenedores")
end
```

`defaults-mensajeria.lua`:
```lua
Name = "defaults-mensajeria"
NamePretty = "Mensajería"
Icon = "internet-chat"
Cache = false

function GetEntries()
  dofile(os.getenv("HOME") .. "/.config/elephant/lib/defaults-helpers.lua")
  return BuildCategoryEntries("mensajeria")
end
```

- [ ] **Step 2: Desplegar y verificar las 9**

```bash
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" apply \
  ~/.config/elephant/menus/defaults-editor.lua \
  ~/.config/elephant/menus/defaults-ia-cli.lua \
  ~/.config/elephant/menus/defaults-terminal.lua \
  ~/.config/elephant/menus/defaults-archivos.lua \
  ~/.config/elephant/menus/defaults-pdf.lua \
  ~/.config/elephant/menus/defaults-imagenes.lua \
  ~/.config/elephant/menus/defaults-correo.lua \
  ~/.config/elephant/menus/defaults-contenedores.lua \
  ~/.config/elephant/menus/defaults-mensajeria.lua
pkill -x elephant; sleep 0.5
setsid -f elephant >/dev/null 2>&1
sleep 1
elephant listproviders | grep -c "^menus:defaults"
for slug in editor ia-cli terminal archivos pdf imagenes correo contenedores mensajeria; do
  n="$(elephant query "menus:defaults-$slug;;10;false" --json | wc -l)"
  echo "$slug: $n entradas"
done
```
Expected: `elephant listproviders | grep -c "^menus:defaults"` = 11 (defaults + defaults-browser + las 9 nuevas); cada categoría reporta el mismo número de entradas que filas tiene su tabla en `category_data()` (editor=7, ia-cli=5, terminal=4, archivos=4, pdf=3, imagenes=4, correo=3, contenedores=2, mensajeria=4).

- [ ] **Step 3: Agregar el wrapper a `archfrican-defaults`**

Insertar el chequeo de Walker dentro de la rama `*)` del `case "${1:-}" in` ya existente (agregado en la Task 6), justo antes de la línea `cat="$(printf ...`, para que `__list`/`__apply` (las otras dos ramas del mismo `case`) nunca pasen por Walker:

```bash
case "${1:-}" in
  __list)  list_category "$2" ;;
  __apply) apply_category "$2" "$3" ;;
  *)
    if command -v walker >/dev/null 2>&1 \
       && elephant listproviders 2>/dev/null | grep -q "^desktopapplications$"; then
      exec walker -m "menus:defaults"
    fi
    cat="$(printf '%s\n' \
      ...
```
(el resto del bloque `*)` queda igual que en la Task 6, solo se agrega el chequeo de Walker como primeras líneas de esa rama).

- [ ] **Step 4: Verificar sintaxis y desplegar**

```bash
bash -n /home/jafricanot/Developer/Archfrican/home/dot_local/bin/executable_archfrican-defaults
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" apply ~/.local/bin/archfrican-defaults
archfrican-defaults __list browser   # confirma que __list sigue funcionando y NO abre Walker
```
Expected: `__list browser` imprime las 5 líneas de siempre (no debe intentar abrir Walker, porque el chequeo está solo en la rama `*)`, no antes del `case`).

- [ ] **Step 5: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add home/dot_config/elephant/menus/defaults-editor.lua \
        home/dot_config/elephant/menus/defaults-ia-cli.lua \
        home/dot_config/elephant/menus/defaults-terminal.lua \
        home/dot_config/elephant/menus/defaults-archivos.lua \
        home/dot_config/elephant/menus/defaults-pdf.lua \
        home/dot_config/elephant/menus/defaults-imagenes.lua \
        home/dot_config/elephant/menus/defaults-correo.lua \
        home/dot_config/elephant/menus/defaults-contenedores.lua \
        home/dot_config/elephant/menus/defaults-mensajeria.lua \
        home/dot_local/bin/executable_archfrican-defaults
git commit -m "$(cat <<'EOF'
feat(walker): remaining 9 defaults categories + archfrican-defaults wrapper

Same BuildCategoryEntries(slug) pattern as defaults-browser for editor,
ia-cli, terminal, archivos, pdf, imagenes, correo, contenedores and
mensajeria. archfrican-defaults now opens "walker -m menus:defaults"
when Walker's up; __list/__apply stay reachable directly regardless,
since they're checked before the Walker branch.
EOF
)"
```

---

### Task 9: `archfrican-setup` → menú TOML nativo con submenús

**Files:**
- Create: `home/dot_config/elephant/menus/setup.toml.tmpl`
- Create: `home/dot_config/elephant/menus/apariencia.toml.tmpl`
- Create: `home/dot_config/elephant/menus/red.toml.tmpl`
- Create: `home/dot_config/elephant/menus/sistema.toml.tmpl`
- Create: `home/dot_config/elephant/menus/privacidad.toml.tmpl`
- Modify: `home/dot_local/bin/executable_archfrican-setup` (agrega wrapper)

**Interfaces:**
- Consumes: `menus:themes` y `menus:pantallas` (Task 5, compartidos con `actions.toml`).
- Produces: `menus:setup`, último de los 5 flagship.

- [ ] **Step 1: Crear `apariencia.toml.tmpl`**

```toml
name = "apariencia"
name_pretty = "Apariencia"
icon = "preferences-desktop-theme"
fixed_order = true

[[entries]]
text = "Cambiar tema"
submenu = "themes"

[[entries]]
text = "Wallpaper / theming dinámico"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-wallpaper" }

[[entries]]
text = "Auto claro/oscuro (alternar)"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-auto-appearance toggle" }

[[entries]]
text = "Blur (alternar)"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-blur toggle" }
```

- [ ] **Step 2: Crear `red.toml.tmpl`**

```toml
name = "red"
name_pretty = "Red / VPN"
icon = "network-wireless"
fixed_order = true

[[entries]]
text = "VPN (Tailscale/WireGuard)"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-vpn" }

[[entries]]
text = "Mullvad (VPN + Browser)"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-mullvad" }

[[entries]]
text = "Editor de red (NetworkManager)"
actions = { run = "nm-connection-editor" }
```

- [ ] **Step 3: Crear `sistema.toml.tmpl`**

```toml
name = "sistema"
name_pretty = "Sistema / hardware"
icon = "preferences-system"
fixed_order = true

[[entries]]
text = "GPU / driver (re-detectar)"
terminal = true
actions = { run = "sh -c 'R=\"{{ .chezmoi.homeDir }}/.archfrican\"; env ARCHFRICAN_ROOT=\"$R\" \"$R/install.sh\" 10-gpu; echo; echo \"Si cambió el driver, reinicia.\"; printf \"(enter para cerrar) \"; read -r _'" }

[[entries]]
text = "Huella digital para sudo"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-fingerprint" }

[[entries]]
text = "Auto-unlock por TPM"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-tpm-unlock" }

[[entries]]
text = "Secure Boot (sbctl)"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-secureboot" }
```

- [ ] **Step 4: Crear `privacidad.toml.tmpl`**

```toml
name = "privacidad"
name_pretty = "Privacidad y respaldo"
icon = "security-high"
fixed_order = true

[[entries]]
text = "Privacidad y telemetría"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-privacy" }

[[entries]]
text = "Respaldo de ~ (restic)"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-backup" }
```

- [ ] **Step 5: Crear `setup.toml.tmpl` (top-level, con `async` para las 2 etiquetas con estado en vivo)**

```toml
name = "setup"
name_pretty = "Configuración"
icon = "preferences-system"
fixed_order = true

[[entries]]
text = "Apps por defecto"
subtext = "navegador, IDE, terminal, PDF, imágenes…"
submenu = "defaults"

[[entries]]
text = "Idioma y región"
async = "sh -c 'printf \"%s / teclado %s\" \"${LANG:-?}\" \"$(cat {{ .chezmoi.homeDir }}/.config/.archfrican-kbd 2>/dev/null || echo us)\"'"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-locale" }

[[entries]]
text = "Pantallas / monitores"
submenu = "pantallas"

[[entries]]
text = "Apariencia"
async = "sh -c 'printf \"tema %s\" \"$(cat {{ .chezmoi.homeDir }}/.config/.archfrican-theme 2>/dev/null || echo adl-dark)\"'"
submenu = "apariencia"

[[entries]]
text = "Energía"
subtext = "perfiles de batería/rendimiento"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-power" }

[[entries]]
text = "Red / VPN"
submenu = "red"

[[entries]]
text = "Accesibilidad"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-a11y" }

[[entries]]
text = "Sistema / hardware"
subtext = "GPU, huella, Secure Boot"
submenu = "sistema"

[[entries]]
text = "Privacidad y respaldo"
submenu = "privacidad"
```

Nota: la entrada "── Terminar" del loop original no tiene equivalente acá — con el cambio de UX ya decidido (cierra tras cada selección, ver spec), no hace falta una opción explícita para salir; `Esc` cierra el menú en cualquier momento, igual que en el resto de Walker.

- [ ] **Step 6: Desplegar y verificar**

```bash
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" apply \
  ~/.config/elephant/menus/setup.toml \
  ~/.config/elephant/menus/apariencia.toml \
  ~/.config/elephant/menus/red.toml \
  ~/.config/elephant/menus/sistema.toml \
  ~/.config/elephant/menus/privacidad.toml
pkill -x elephant; sleep 0.5
setsid -f elephant >/dev/null 2>&1
sleep 1
elephant listproviders | grep -E "^menus:(setup|apariencia|red|sistema|privacidad)$"
elephant query "menus:setup;;15;false" --json | wc -l
elephant query "menus:setup;;15;false" --json | grep -o '"text":"Idioma[^}]*' 
```
Expected: los 5 providers listados; `menus:setup` devuelve 9 líneas; la entrada de "Idioma" muestra en su JSON un `subtext` (o campo equivalente que Walker resuelva desde `async`) con el idioma/teclado reales del sistema, no literal `${LANG:-?}` sin resolver — si aparece sin resolver, revisar la sintaxis de `async` contra `elephant generate doc menus` antes de continuar (campo documentado como "Shell command returning dynamic content", pero no se confirmó en esta sesión el nombre exacto del campo de salida en el JSON — verificarlo acá).

- [ ] **Step 7: Agregar el wrapper a `archfrican-setup`**

Insertar antes del `while :; do` (que se elimina — la versión nativa no usa loop, ver Step 5):

```bash
#!/usr/bin/env bash
# archfrican-setup — the settings assistant ("Asistente de configuración"). A categorized hub over the
# existing Archfrican helpers + the runtime gaps (language, default IDE/PDF/image/file-manager…).
# Offered once on first boot (archfrican-welcome-notify) and always from the actions hub (⌘+Shift+A).
set -euo pipefail
B="$HOME/.local/bin"
have() { command -v "$1" >/dev/null 2>&1; }
have fuzzel || { echo "fuzzel required" >&2; exit 1; }
flip() { if [ "$("$1" status 2>/dev/null)" = on ]; then echo off; else echo on; fi; }
launch() { if have "$1"; then "$@"; fi; }
theme_now() { cat "$HOME/.config/.archfrican-theme" 2>/dev/null || echo adl-dark; }
kbd_now()   { cat "$HOME/.config/.archfrican-kbd" 2>/dev/null || echo us; }

# Native menu (menus/setup.toml) when Walker/elephant are up; fuzzel fallback below otherwise.
if command -v walker >/dev/null 2>&1 \
   && elephant listproviders 2>/dev/null | grep -q "^desktopapplications$"; then
  exec walker -m "menus:setup"
fi

while :; do
  ...
```
(el resto del `while :; do ... done` original queda exactamente igual — es el fallback).

- [ ] **Step 8: Verificar sintaxis y desplegar**

```bash
bash -n /home/jafricanot/Developer/Archfrican/home/dot_local/bin/executable_archfrican-setup
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" apply ~/.local/bin/archfrican-setup
```

- [ ] **Step 9: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add home/dot_config/elephant/menus/setup.toml.tmpl \
        home/dot_config/elephant/menus/apariencia.toml.tmpl \
        home/dot_config/elephant/menus/red.toml.tmpl \
        home/dot_config/elephant/menus/sistema.toml.tmpl \
        home/dot_config/elephant/menus/privacidad.toml.tmpl \
        home/dot_local/bin/executable_archfrican-setup
git commit -m "$(cat <<'EOF'
feat(walker): native menus:setup provider, closes the 5-script migration

Reuses menus:themes and menus:pantallas (already shared with actions).
The old "stays open, loop until Terminar" UX is gone — matches Walker's
close-after-selection behavior everywhere else, as decided in the spec.
Idioma/Apariencia entries use "async" for their live status text.
EOF
)"
```

---

### Task 10: Reiniciar `elephant` automáticamente después de cada `chezmoi apply`

**Files:**
- Modify: `home/run_after_99-apply-theme.sh.tmpl`

**Interfaces:**
- Consumes: nada.
- Produces: cualquier archivo de menú nuevo/editado bajo `~/.config/elephant/` queda detectado sin pasos manuales después de `chezmoi apply` — cierra el punto de "Despliegue" del spec.

- [ ] **Step 1: Leer el hook actual completo**

```bash
cat /home/jafricanot/Developer/Archfrican/home/run_after_99-apply-theme.sh.tmpl
```
(ya se leyó su contenido completo durante la sesión de diseño de la Fase 1 — confirmar que no cambió antes de editarlo, dado que este archivo vive fuera del alcance directo de este proyecto y pudo haberse tocado en otra sesión).

- [ ] **Step 2: Agregar el restart de `elephant` al final del hook**

Agregar este bloque al final del archivo (después de la sección de blur, que es lo último que hace hoy):

```bash
# Reinicia elephant para que detecte menús nuevos/editados bajo ~/.config/elephant/menus/ y
# ~/.config/elephant/lib/ — sin esto, un `chezmoi apply` que agregue o cambie un archivo de menú
# no se refleja hasta el próximo login. No falla el hook si elephant no está instalado (fresh
# install antes de que 20-niri-desktop.sh corra, o un perfil sin Walker).
if command -v elephant >/dev/null 2>&1; then
  pkill -x elephant 2>/dev/null || true
  sleep 0.5
  setsid -f elephant >/dev/null 2>&1 || true
fi
```

- [ ] **Step 3: Verificar sintaxis**

```bash
bash -n /home/jafricanot/Developer/Archfrican/home/run_after_99-apply-theme.sh.tmpl
```
Expected: sin salida (el `.tmpl` con `{{ }}` de chezmoi sigue siendo bash válido fuera de esas expresiones, igual que ya lo era antes de este cambio — mismo patrón que `config.kdl.tmpl`).

- [ ] **Step 4: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add home/run_after_99-apply-theme.sh.tmpl
git commit -m "$(cat <<'EOF'
feat(hooks): restart elephant after chezmoi apply picks up menu changes

Menu files under ~/.config/elephant/menus/ and lib/ only get detected
by elephant on process start. Without this, a fresh chezmoi apply that
adds or edits a menu silently does nothing until the next login.
EOF
)"
```

---

### Task 11: Desplegar todo y verificar interactivamente

**Files:**
- Ninguno se modifica — despliegue final y verificación con el usuario presente.

**Interfaces:**
- Consumes: todos los commits de las Tareas 1-10.
- Produces: los 5 atajos (`Mod+Shift+A/K/T` directos, `Mod+Shift+A`→"Apps por defecto"/"Asistente" indirectos) abren sus versiones nativas.

- [ ] **Step 1: Previsualizar el diff completo**

```bash
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" diff
```
Revisar que coincide con lo esperado: los 5 scripts wrapper, los ~20 archivos nuevos bajo `home/dot_config/elephant/`, el hook actualizado. Ningún archivo fuera de este proyecto debería aparecer — si aparece algo inesperado, no es de esta tarea, no tocarlo (mismo criterio que en la Fase 1).

- [ ] **Step 2: Aplicar — STOP, no correr el comando de abajo todavía**

Igual que en la Fase 1 (Plan `2026-07-02-walker-menu-retire-duplicates.md`, Task 6): `~/.config/niri/config.kdl` no se toca en este plan, pero SÍ hay archivos nuevos en `~/.config/elephant/` — esos no piden confirmación (son nuevos, sin drift). Aun así, **no ejecutar el comando de abajo sin que el usuario confirme explícitamente en la conversación** que quiere desplegar — es un cambio grande (11 tareas) al launcher que usa activamente.

```bash
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" apply
pkill -x elephant; sleep 0.5
setsid -f elephant >/dev/null 2>&1
```

- [ ] **Step 3: Verificación interactiva (con el usuario presente, abre ventanas reales)**

Pedirle al usuario que confirme, uno por uno:
- `Mod+Shift+T` abre Walker en `menus:layout` con las 7 opciones.
- `Mod+Shift+K` abre Walker en `menus:keys`, agrupado por categoría vía `subtext`, buscable.
- `Mod+Shift+A` abre Walker en `menus:actions`, las 51 opciones, cierra al elegir una.
- Desde `menus:actions`: "Cambiar tema…" y "Pantallas / monitores" abren sus submenús.
- "Apps por defecto" (desde `archfrican-actions` o directo) abre `menus:defaults`, una categoría muestra apps instaladas/no instaladas correctamente, elegir una ya instalada aplica el default sin error.
- "Asistente de configuración" abre `menus:setup`, con "Idioma y región" y "Apariencia" mostrando el idioma/tema reales en su subtexto.

- [ ] **Step 4: Commit final si hubo ajustes durante la verificación**

Solo si el Step 3 reveló algo que corregir (ej. el campo `async` no se resolvió como se esperaba en el Step 6 de la Task 9 — ver la nota de verificación ahí). Si todo funcionó tal cual, no hace falta commit adicional.
