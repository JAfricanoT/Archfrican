# Retirar scripts de launcher duplicados con Walker (Fase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminar `archfrican-calc`, `archfrican-find`, `archfrican-window`, `archfrican-emoji` y `archfrican-websearch` — duplican providers nativos de Walker (`calc`, `files`, `windows`, `symbols`, `websearch`) — y apuntar sus atajos/entradas de menú al provider nativo correspondiente vía `walker -m <provider>`.

**Architecture:** Los 4 atajos de niri con bind directo (`Mod+Shift+C/G/W/V`) pasan de `spawn "archfrican-X"` a `spawn "walker" "-m" "<provider>"`. Las entradas de `archfrican-actions` que abrían estos 5 scripts se reescriben para invocar `walker -m <provider>` directamente. `archfrican-spotlight` pierde las 5 entradas correspondientes de su rama de fallback (ese fallback solo corre cuando Walker está confirmado ausente, así que no puede depender de `walker -m` — se elimina la entrada, no se repunta). Ninguno de estos 5 scripts lleva wrapper de fallback: son duplicados puros, sin lógica propia que proteger.

**Tech Stack:** bash, KDL (niri config), chezmoi (dotfiles), Walker/elephant (ya instalados).

## Global Constraints

- Spec de referencia: `docs/superpowers/specs/2026-07-02-walker-menu-integration-design.md`.
- Ningún commit debe incluir atribución a Claude/IA ni trailer `Co-Authored-By` (preferencia del usuario para este repo).
- Cada tarea termina con un commit de checkpoint independiente — no acumular cambios de varias tareas en un solo commit.
- `niri validate` debe pasar después de cualquier edición a `binds{}` en `config.kdl.tmpl`.
- `bash -n <script>` debe pasar después de cualquier edición a un script bash.
- No usar `chezmoi apply --force` ni desplegar al sistema real sin que el usuario lo confirme explícitamente (el repo tiene contenido gestionado en vivo — bloque de monitores, tema — que exige confirmación interactiva de chezmoi; ver Tarea 6).

---

### Task 1: Confirmar que no hay referencias no catalogadas a los 5 scripts a retirar

**Files:**
- Ninguno se modifica — esta tarea es solo de verificación, previa a las ediciones destructivas de las tareas siguientes.

**Interfaces:**
- Consumes: nada.
- Produces: confirmación (o lista de excepciones) de que los únicos llamadores de `archfrican-calc`, `archfrican-find`, `archfrican-window`, `archfrican-emoji`, `archfrican-websearch` son los ya catalogados: `home/dot_config/niri/config.kdl.tmpl` (binds directos) y `home/dot_local/bin/executable_archfrican-actions`/`executable_archfrican-spotlight` (menús). Las tareas 2-5 dependen de que esta lista esté completa.

- [ ] **Step 1: Grep de referencias cruzadas**

Run:
```bash
cd /home/jafricanot/Developer/Archfrican
for s in archfrican-calc archfrican-find archfrican-window archfrican-emoji archfrican-websearch; do
  echo "=== $s ==="
  grep -rn "$s" --include='*.tmpl' --include='executable_*' --include='*.sh' . \
    | grep -v "home/dot_local/bin/executable_$s"
done
```
Expected: cada bloque `=== archfrican-X ===` solo debe mostrar líneas dentro de `home/dot_config/niri/config.kdl.tmpl`, `home/dot_local/bin/executable_archfrican-actions` o `home/dot_local/bin/executable_archfrican-spotlight`. Si aparece cualquier otro archivo, anotarlo — las tareas 2-5 deben actualizarse para cubrirlo antes de continuar.

- [ ] **Step 2: Confirmar el resultado**

No hay commit en esta tarea (es de solo lectura). Si el grep no arrojó sorpresas, continuar a la Tarea 2.

---

### Task 2: Apuntar los 4 atajos directos a los providers nativos de Walker

**Files:**
- Modify: `home/dot_config/niri/config.kdl.tmpl:224` (Mod+Shift+V, sección "Portapapeles")
- Modify: `home/dot_config/niri/config.kdl.tmpl:228-230` (Mod+Shift+W/C/G, sección "Buscadores y paneles")

**Interfaces:**
- Consumes: nada.
- Produces: los binds `Mod+Shift+C`, `Mod+Shift+G`, `Mod+Shift+W`, `Mod+Shift+V` en `config.kdl.tmpl` invocan `walker -m <provider>` en vez de los scripts retirados. Las tareas 3-5 no dependen de esto, pero deben mantenerse consistentes en terminología ("provider nativo de Walker").

- [ ] **Step 1: Editar el bind de portapapeles (línea 222-224)**

Contenido actual:
```kdl
    // nota: surge del daemon cliphist ya iniciado al arrancar
    // Portapapeles
    Mod+Shift+V { spawn "sh" "-c" "cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"; }   // clipboard history
```

Nuevo contenido:
```kdl
    // Portapapeles
    Mod+Shift+V { spawn "walker" "-m" "clipboard"; }   // historial de portapapeles (provider nativo de Walker)
```

(La nota sobre el daemon `cliphist` se quita de aquí porque ya no aplica a este bind — `cliphist` sigue vivo solo como respaldo dentro de `archfrican-spotlight`, ver Tarea 4.)

- [ ] **Step 2: Editar los binds de ventanas/calculadora/archivos (líneas 226-230)**

Contenido actual:
```kdl
    // Buscadores y paneles
    Mod+Shift+A { spawn "{{ .chezmoi.homeDir }}/.local/bin/archfrican-actions"; }   // actions / settings hub
    Mod+Shift+W { spawn "{{ .chezmoi.homeDir }}/.local/bin/archfrican-window"; }    // window switcher
    Mod+Shift+C { spawn "{{ .chezmoi.homeDir }}/.local/bin/archfrican-calc"; }      // calculator
    Mod+Shift+G { spawn "{{ .chezmoi.homeDir }}/.local/bin/archfrican-find"; }      // search files
```

Nuevo contenido:
```kdl
    // Buscadores y paneles
    Mod+Shift+A { spawn "{{ .chezmoi.homeDir }}/.local/bin/archfrican-actions"; }   // actions / settings hub
    Mod+Shift+W { spawn "walker" "-m" "windows"; }    // selector de ventanas (provider nativo de Walker)
    Mod+Shift+C { spawn "walker" "-m" "calc"; }       // calculadora (provider nativo de Walker)
    Mod+Shift+G { spawn "walker" "-m" "files"; }      // buscar archivos (provider nativo de Walker)
```

- [ ] **Step 3: Validar el KDL resultante**

Run:
```bash
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" cat ~/.config/niri/config.kdl > /tmp/config.kdl.check
niri validate --config /tmp/config.kdl.check
rm /tmp/config.kdl.check
```
Expected: última línea `INFO niri: config is valid`.

- [ ] **Step 4: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add home/dot_config/niri/config.kdl.tmpl
git commit -m "$(cat <<'EOF'
feat(niri): point calc/find/window/clipboard binds at native Walker providers

Mod+Shift+C/G/W/V now spawn "walker -m <provider>" directly instead of
the archfrican-calc/find/window scripts and the inline cliphist pipeline,
all of which duplicated providers Walker already ships (calc, files,
windows, clipboard).
EOF
)"
```

---

### Task 3: Reescribir las 5 entradas correspondientes en `archfrican-actions`

**Files:**
- Modify: `home/dot_local/bin/executable_archfrican-actions:89-93`

**Interfaces:**
- Consumes: nada.
- Produces: las entradas "Portapapeles", "Emoji / símbolos", "Calculadora", "Buscar archivos" y "Buscar en la web" del menú de `archfrican-actions` invocan `walker -m <provider>` en vez de los 5 scripts retirados.

- [ ] **Step 1: Editar el bloque `case` (líneas 89-93)**

Contenido actual:
```bash
  "Portapapeles"*)       sh -c 'cliphist list | fuzzel --dmenu | cliphist decode | wl-copy' ;;
  "Emoji"*)              "$B/archfrican-emoji" ;;
  "Calculadora"*)        "$B/archfrican-calc" ;;
  "Buscar archivos"*)    "$B/archfrican-find" ;;
  "Buscar en la web"*)   "$B/archfrican-websearch" ;;
```

Nuevo contenido:
```bash
  "Portapapeles"*)       walker -m clipboard ;;
  "Emoji"*)              walker -m symbols ;;
  "Calculadora"*)        walker -m calc ;;
  "Buscar archivos"*)    walker -m files ;;
  "Buscar en la web"*)   walker -m websearch ;;
```

Nota para la Fase 2: cuando `archfrican-actions` reciba su propio wrapper de fallback (Plan 2), estas 5 líneas solo funcionan con Walker presente — igual que el resto del archivo en Fase 1, no llevan protección propia. Si Walker llegara a estar ausente, quedan como no-op silencioso (la Fase 2 debe decidir si eso es aceptable o si conviene ocultarlas del todo en la rama de fallback).

- [ ] **Step 2: Verificar sintaxis**

Run: `bash -n /home/jafricanot/Developer/Archfrican/home/dot_local/bin/executable_archfrican-actions`
Expected: sin salida (exit code 0).

- [ ] **Step 3: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add home/dot_local/bin/executable_archfrican-actions
git commit -m "$(cat <<'EOF'
feat(actions): route clipboard/emoji/calc/find/websearch entries to Walker

These five archfrican-actions entries opened scripts that duplicated
Walker's own providers; they now call "walker -m <provider>" directly.
EOF
)"
```

---

### Task 4: Simplificar la rama de fallback de `archfrican-spotlight`

**Files:**
- Modify: `home/dot_local/bin/executable_archfrican-spotlight:23-29` (definición de modos)
- Modify: `home/dot_local/bin/executable_archfrican-spotlight:52-63` (`build_list`)
- Modify: `home/dot_local/bin/executable_archfrican-spotlight:79-88` (dispatch `case`)

**Interfaces:**
- Consumes: nada.
- Produces: la rama de fallback de `archfrican-spotlight` (solo corre cuando `have walker && have elephant` es falso) ya no ofrece "Buscar archivos…", "Buscar en la web…", "Calculadora…", "Ventanas abiertas…" ni "Emojis…" — esos modos no tienen implementación propia una vez retirados los scripts, y `walker -m` no es una opción válida dentro de esta rama (es precisamente la rama para cuando Walker no está disponible). "Portapapeles…" se mantiene con su pipeline `cliphist` inline sin cambios, porque sigue siendo self-contained y es el único consumidor restante de `cliphist` en el repo.

- [ ] **Step 1: Quitar las 5 variables de modo retiradas (líneas 23-29)**

Contenido actual:
```bash
M_FIND="Buscar archivos…"
M_WEB="Buscar en la web…"
M_CALC="Calculadora…"
M_WIN="Ventanas abiertas…"
M_CLIP="Portapapeles…"
M_EMOJI="Emojis…"
M_ACT="Acciones y ajustes…"
```

Nuevo contenido:
```bash
M_CLIP="Portapapeles…"
M_ACT="Acciones y ajustes…"
```

- [ ] **Step 2: Quitar las entradas correspondientes de `build_list()` (líneas 52-63)**

Contenido actual:
```bash
build_list() {
  printf '%s\0icon\x1fsystem-search\n'              "$M_FIND"
  printf '%s\0icon\x1finternet-web-browser\n'       "$M_WEB"
  printf '%s\0icon\x1faccessories-calculator\n'     "$M_CALC"
  printf '%s\0icon\x1fpreferences-system-windows\n' "$M_WIN"
  printf '%s\0icon\x1fedit-paste\n'                 "$M_CLIP"
  printf '%s\0icon\x1fface-smile\n'                 "$M_EMOJI"
  printf '%s\0icon\x1fpreferences-system\n'         "$M_ACT"
  sort -t "$TAB" -k1,1 -u "$idx" | while IFS="$TAB" read -r name _id icon; do
    if [ -n "$icon" ]; then printf '%s\0icon\x1f%s\n' "$name" "$icon"; else printf '%s\n' "$name"; fi
  done
}
```

Nuevo contenido:
```bash
build_list() {
  printf '%s\0icon\x1fedit-paste\n'                 "$M_CLIP"
  printf '%s\0icon\x1fpreferences-system\n'         "$M_ACT"
  sort -t "$TAB" -k1,1 -u "$idx" | while IFS="$TAB" read -r name _id icon; do
    if [ -n "$icon" ]; then printf '%s\0icon\x1f%s\n' "$name" "$icon"; else printf '%s\n' "$name"; fi
  done
}
```

- [ ] **Step 3: Quitar las entradas correspondientes del dispatch `case` (líneas 79-88)**

Contenido actual:
```bash
case "$sel" in
  "$M_FIND") "$B/archfrican-find" ;;
  "$M_WEB")  "$B/archfrican-websearch" ;;
  "$M_CALC") "$B/archfrican-calc" ;;
  "$M_WIN")  "$B/archfrican-window" ;;
  "$M_CLIP") sh -c 'cliphist list | fuzzel --dmenu --prompt "   " | cliphist decode | wl-copy' ;;
  "$M_EMOJI") "$B/archfrican-emoji" ;;
  "$M_ACT")  "$B/archfrican-actions" ;;
  *)         launch_app "$sel" ;;
esac
```

Nuevo contenido:
```bash
case "$sel" in
  "$M_CLIP") sh -c 'cliphist list | fuzzel --dmenu --prompt "   " | cliphist decode | wl-copy' ;;
  "$M_ACT")  "$B/archfrican-actions" ;;
  *)         launch_app "$sel" ;;
esac
```

- [ ] **Step 4: Verificar sintaxis**

Run: `bash -n /home/jafricanot/Developer/Archfrican/home/dot_local/bin/executable_archfrican-spotlight`
Expected: sin salida (exit code 0).

- [ ] **Step 5: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add home/dot_local/bin/executable_archfrican-spotlight
git commit -m "$(cat <<'EOF'
refactor(spotlight): drop fallback modes that duplicate retired scripts

The fuzzel-only fallback path (Walker/elephant absent) can no longer
offer file search, web search, calc, or window-switching modes now that
their backing scripts are gone — those modes have no self-contained
implementation left. Clipboard stays, since it's still self-contained
(inline cliphist) and doesn't depend on Walker being present.
EOF
)"
```

---

### Task 5: Eliminar los 5 scripts retirados

**Files:**
- Delete: `home/dot_local/bin/executable_archfrican-calc`
- Delete: `home/dot_local/bin/executable_archfrican-find`
- Delete: `home/dot_local/bin/executable_archfrican-window`
- Delete: `home/dot_local/bin/executable_archfrican-emoji`
- Delete: `home/dot_local/bin/executable_archfrican-websearch`

**Interfaces:**
- Consumes: confirmación de la Tarea 1 de que no hay más referencias, y de las Tareas 2-4 de que todos los llamadores conocidos ya fueron actualizados.
- Produces: los 5 archivos dejan de existir en el repo; `chezmoi apply` los eliminará de `~/.local/bin/` en el siguiente despliegue (Tarea 6).

- [ ] **Step 1: Grep final de seguridad antes de borrar**

Run:
```bash
cd /home/jafricanot/Developer/Archfrican
for s in archfrican-calc archfrican-find archfrican-window archfrican-emoji archfrican-websearch; do
  echo "=== $s ==="
  grep -rn "$s" --include='*.tmpl' --include='executable_*' . | grep -v "home/dot_local/bin/executable_$s"
done
```
Expected: sin resultados en ningún bloque (las tareas 2-4 ya limpiaron todas las referencias conocidas).

- [ ] **Step 2: Eliminar los archivos**

```bash
cd /home/jafricanot/Developer/Archfrican
git rm home/dot_local/bin/executable_archfrican-calc \
       home/dot_local/bin/executable_archfrican-find \
       home/dot_local/bin/executable_archfrican-window \
       home/dot_local/bin/executable_archfrican-emoji \
       home/dot_local/bin/executable_archfrican-websearch
```

- [ ] **Step 3: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git commit -m "$(cat <<'EOF'
chore(bin): remove archfrican-calc/find/window/emoji/websearch

Duplicated Walker's built-in calc/files/windows/symbols/websearch
providers. All call sites (niri binds, archfrican-actions,
archfrican-spotlight) were already repointed to "walker -m <provider>"
in prior commits on this branch.
EOF
)"
```

---

### Task 6: Desplegar y verificar en el sistema real

**Files:**
- Ninguno se modifica — esta tarea despliega los cambios ya commiteados y los verifica interactivamente.

**Interfaces:**
- Consumes: los commits de las Tareas 2-5.
- Produces: `~/.config/niri/config.kdl` y `~/.local/bin/` reflejan los cambios; los 4 atajos y las 2 entradas de menú funcionan contra los providers nativos de Walker.

- [ ] **Step 1: Previsualizar el diff sin aplicar**

```bash
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" diff
```
Revisar que el diff mostrado coincide con lo esperado: los 4 binds y las 5 líneas de `archfrican-actions`/`archfrican-spotlight` cambiados, los 5 archivos `archfrican-{calc,find,window,emoji,websearch}` eliminados de `~/.local/bin/`.

- [ ] **Step 2: Aplicar — STOP, no correr el comando de abajo todavía**

`~/.config/niri/config.kdl` tiene contenido gestionado en vivo por `archfrican-displays` (bloque de monitores) fuera del control de chezmoi, así que `chezmoi apply` va a pedir confirmación interactiva o necesita `--force`. **No ejecutar el comando de abajo hasta que el usuario haya confirmado explícitamente en la conversación que quiere aplicar el cambio** — usar AskUserQuestion o preguntar directamente: ¿lo aplica el usuario en su propia terminal (respondiendo el prompt interactivo normal de chezmoi), o preferís que se corra acá con `--force` una vez que entienda por qué chezmoi pide confirmación? Mismo criterio ya usado en este repo (ver commit `8994a8c` y la sesión que lo precedió) — esto no es opcional ni un formalismo, es un despliegue real a un escritorio en uso.

Recién con esa confirmación explícita, correr:
```bash
cd /home/jafricanot/Developer/Archfrican
chezmoi -S "$(pwd)/home" apply --force
```

- [ ] **Step 3: Verificación interactiva (con el usuario presente)**

Esto abre ventanas reales en la pantalla — no ejecutar de forma desatendida. Pedirle al usuario que confirme, uno por uno:
- `Mod+Shift+C` abre Walker directo en modo calculadora.
- `Mod+Shift+G` abre Walker directo en modo archivos.
- `Mod+Shift+W` abre Walker directo en modo ventanas.
- `Mod+Shift+V` abre Walker directo en modo portapapeles.
- `Mod+Shift+A` → "Emoji / símbolos" y "Buscar en la web" abren Walker en los modos correspondientes.
- `Mod+Space` (archfrican-spotlight) sigue abriendo Walker con normalidad (no debería haber cambiado nada en su rama principal).

- [ ] **Step 4: Commit final si hubo ajustes durante la verificación**

Solo si el Step 3 reveló algo que corregir. Si todo funcionó tal cual, no hace falta commit adicional — Task 5 ya dejó el árbol en el estado final.
