# Integrar los menús de Archfrican como providers nativos de Walker

## Contexto

`walker` (GTK4, backend `elephant`) y `fuzzel` corren ambos en este sistema. Walker/elephant están pensados como el launcher primario (`spawn-at-startup "elephant"` y `spawn-at-startup "walker" "--gapplication-service"` en `home/dot_config/niri/config.kdl.tmpl`), pero en la práctica solo `archfrican-spotlight` (`Mod+Space`) los invoca de verdad. El resto de los ~50 scripts `archfrican-*` bajo `home/dot_local/bin/` — acciones, atajos de teclado, apps por defecto, calculadora, buscador de archivos, selector de ventanas, emojis, búsqueda web, etc. — abren su propia ventana `fuzzel --dmenu` independiente, con su propio atajo de niri, sin ninguna relación con Walker. El resultado (motivo de este proyecto): al usar el launcher, cada herramienta "se siente" como una app distinta en vez de un solo sistema integrado.

Investigación previa (ver conversación) confirmó dos hechos clave que habilitan una solución real, no solo cosmética:

1. **`elephant-menus` está instalado pero nunca configurado.** Es el provider nativo de Walker para menús/acciones custom (TOML o Lua), documentado en detalle vía `elephant generate doc menus` (fuente más confiable que la web, porque lee del binario realmente instalado — versión `2.21.0-1`).
2. **Se probó en vivo, de punta a punta, en esta máquina**: se creó un archivo Lua de prueba en `~/.config/elephant/menus/`, se reinició `elephant`, y `elephant query "menus:zz-spike-test;;10;false" --json` devolvió las entradas — incluyendo una generada dinámicamente vía `io.popen("date +%H:%M:%S")`, confirmando que Lua puede invocar comandos de shell en vivo para poblar un menú, tal como está documentado. El archivo de prueba fue eliminado y `elephant` quedó restaurado a su estado original al terminar la prueba.

## Alcance

**Este proyecto cubre dos fases, ambas a implementar ahora:**

- **Fase 1 — Retirar duplicados**: 5 scripts (`archfrican-calc`, `archfrican-find`, `archfrican-window`, `archfrican-emoji`, `archfrican-websearch`) más el patrón inline de portapapeles (dentro de `archfrican-actions` y `archfrican-spotlight`) duplican providers que Walker ya trae de fábrica (`calc`, `files`, `windows`, `symbols`, `websearch`, `clipboard`). Se eliminan y sus atajos pasan a abrir el provider nativo directo.
- **Fase 2 — Migración nativa de los 5 flagship**: `archfrican-actions`, `archfrican-keys`, `archfrican-defaults`, `archfrican-layout` y `archfrican-setup` pasan a tener una versión nativa en `~/.config/elephant/menus/`, alcanzable tanto por su atajo de niri de siempre (vía un wrapper) como desde dentro del buscador de Walker.

**Explícitamente fuera de alcance de este proyecto** (mismo patrón, para un spec/plan futuro separado — ~11 scripts de menor tráfico, todos alcanzables solo a través de `archfrican-actions`/`archfrican-setup`, nunca por atajo propio): `archfrican-mullvad`, `archfrican-power`, `archfrican-migrate`, `archfrican-rollback`, `archfrican-privacy`, `archfrican-vpn`, `archfrican-a11y`, `archfrican-cloud`, `archfrican-browser`, `archfrican-session`, `archfrican-welcome`.

**No se tocan en ningún alcance** (no se benefician de convertirse en menú nativo — requieren terminal interactiva, sudo, o simplemente no son pickers): los wizards de terminal (`archfrican-git`, `archfrican-tpm-unlock`, `archfrican-secureboot`, `archfrican-plymouth`, `archfrican-webapp`, `archfrican-wallpaper`, partes de `archfrican-backup`/`archfrican-migrate`) y los ~18 scripts que son toggles, daemons o módulos de waybar sin UI de selección (`archfrican-blur`, `archfrican-focus`, `archfrican-lock`, `archfrican-quit-app`, etc.).

## Arquitectura

### Patrón de fallback (extiende el que ya usa `archfrican-spotlight`)

Cada uno de los 5 scripts de la Fase 2 se reescribe como un dispatcher delgado que prueba primero la ruta nativa y cae a la lógica fuzzel original si Walker/elephant no responden:

```bash
if command -v walker >/dev/null 2>&1 \
   && elephant listproviders 2>/dev/null | grep -q "^desktopapplications$"; then
  exec walker -m "menus:actions"
fi
# ... lógica fuzzel original, sin cambios, tal cual está hoy ...
```

El atajo de niri correspondiente **no cambia** — sigue apuntando al mismo script (`archfrican-actions`, `archfrican-keys`, etc.), que ahora decide internamente qué camino tomar. Los 5 scripts de la Fase 1 (retirados) **no** llevan este wrapper: son duplicados puros sin lógica propia que proteger, así que se eliminan directamente y su atajo pasa a invocar `walker -m <provider>` sin intermediario.

### TOML vs. Lua: regla de decisión

- **TOML** para listas cuyo contenido no depende de estado en tiempo de ejecución fila por fila (aunque el menú tenga un puñado de labels que se refrescan solos vía el campo `async` de una entrada individual — eso no obliga a todo el archivo a ser Lua).
- **Lua** (`GetEntries()`) solo para lo que necesita calcular la lista completa en el momento (leer `pacman -Q` por fila, parsear `config.kdl` en vivo, listar monitores conectados, etc.). El patrón siempre es **Lua llama a `io.popen()` sobre la MISMA lógica bash/awk que ya existe** — nunca reescribir esa lógica en Lua desde cero. Esto es literalmente lo mismo que ya hicimos con `archfrican-keys` en la sesión anterior (parseo vía `awk` como única fuente de verdad); acá se reutiliza el mismo principio, invocado desde Lua en vez de desde bash.
- Campos de configuración confirmados en `elephant generate doc menus` que se usan en este diseño:
  - `fixed_order = true` — **obligatorio** en todo menú migrado con orden intencional (Walker ordena alfabéticamente por default, lo que rompería el agrupamiento que ya se armó a mano en `config.kdl.tmpl`).
  - `refresh_on_change = [...]` + `cache = true` — para menús Lua que dependen de archivos concretos (ej. `keys` con `config.kdl` y `/etc/keyd/default.conf`): recalcula solo cuando esos archivos cambian de verdad, no en cada consulta.
  - `terminal = true` (a nivel entry) — mapea 1:1 con el patrón `ghostty -e sh -c "..."` que ya usan los scripts actuales para instalaciones/comandos interactivos.
  - `submenu = "nombre"` (o `"dmenu:nombre"`) — referencia a otro archivo de menú; así los flujos de dos niveles (categoría → app, categoría → subcategoría) se modelan como varios archivos chicos en vez de un monolito.

### Layout de archivos

Nuevos archivos bajo `home/dot_config/elephant/menus/*.toml` y `*.lua` (mismo directorio de `home/dot_config/elephant/websearch.toml`, ya existente y gestionado por chezmoi sin cambios adicionales de tooling).

## Fase 1 — Retirar duplicados

| Atajo hoy | Script (se elimina del repo) | Provider nativo |
|---|---|---|
| `Mod+Shift+C` | `archfrican-calc` | `walker -m calc` |
| `Mod+Shift+G` | `archfrican-find` | `walker -m files` |
| `Mod+Shift+W` | `archfrican-window` | `walker -m windows` |
| `Mod+Shift+V` | inline `cliphist \| fuzzel` en `config.kdl.tmpl` | `walker -m clipboard` |
| *(solo vía menú)* | `archfrican-emoji` | `walker -m symbols` |
| *(solo vía menú)* | `archfrican-websearch` | `walker -m websearch` (`~/.config/elephant/websearch.toml` ya replica su tabla de bangs — la migración de facto ya está hecha) |

Pasos:
1. Antes de borrar cada script, `grep -rn "archfrican-<nombre>"` sobre todo el repo para confirmar que ningún otro script (fuera de los ya catalogados: `archfrican-actions`, `archfrican-spotlight`) lo invoca.
2. Actualizar `home/dot_config/niri/config.kdl.tmpl`: los 4 binds de la tabla pasan de `spawn "archfrican-X"` (o el inline de cliphist) a `spawn "walker" "-m" "<provider>"`.
3. Quitar de `archfrican-actions` las entradas que abrían `archfrican-emoji`/`archfrican-websearch`/la línea inline de portapapeles, reemplazándolas por las mismas líneas apuntando a `walker -m symbols` / `walker -m websearch` / `walker -m clipboard`.
4. Quitar de la rama fallback de `archfrican-spotlight` las mismas referencias (esa rama sigue existiendo — es el fallback de `archfrican-spotlight` mismo, no de estos 5 — pero ya no debe ofrecer modos que ya no existen como scripts).
5. Eliminar los 5 archivos `home/dot_local/bin/executable_archfrican-{calc,find,window,emoji,websearch}`.

## Fase 2 — Migración nativa de los 5 flagship

| Script | Formato | Estructura de archivos | Notas de diseño |
|---|---|---|---|
| `archfrican-layout` | TOML puro | `menus/layout.toml` | 7 entradas fijas, cada una con `actions = { apply = "niri msg action ..." }`. El caso más simple, sirve de plantilla de referencia para los demás. |
| `archfrican-actions` | TOML (top-level) + Lua solo en el submenú de temas | `menus/actions.toml` + `menus/themes.lua` (para "Cambiar tema…", que lee `~/.archfrican/themes/*/` en vivo — el único submenú de `archfrican-actions` con contenido genuinamente dinámico) | La mayoría de las ~52 entradas son texto→comando fijo → TOML. El submenú "Pantallas" (Organizar/Guardar) es estático de 2 ítems → TOML, sin Lua; de paso queda deduplicado, porque hoy está copiado literal tanto en `archfrican-actions` como en `archfrican-setup`. Los labels que hoy muestran estado en vivo (ej. toggle de auto-apariencia ON/OFF) usan el campo `async` de la entrada TOML para refrescar solo ese texto, sin necesidad de convertir todo el archivo a Lua. Si al implementar aparece alguna otra entrada con contenido dinámico no identificado en este spec, se resuelve con el mismo criterio: Lua solo para esa entrada puntual, nunca para todo el archivo. |
| `archfrican-keys` | Lua | `menus/keys.lua` | `GetEntries()` hace `io.popen()` sobre el mismo pipeline `awk` de `home/dot_local/bin/executable_archfrican-keys`. `refresh_on_change = ["~/.config/niri/config.kdl", "/etc/keyd/default.conf"]`, `cache = true`. La categoría (hoy un separador visual `── X ──` en fuzzel) pasa al campo `subtext` de cada entrada — Walker no tiene un concepto nativo de header de sección, así que se pierde el bloque visual separador a cambio de que cada fila diga su categoría junto a la descripción. |
| `archfrican-defaults` | Top-level TOML (categorías) + un Lua por categoría | `menus/defaults.toml` + `menus/defaults-browser.lua`, `menus/defaults-editor.lua`, ... (una por cada categoría que hoy pasa por `category()` en el script actual) | El picker de categorías es fijo → TOML con `submenu` por fila. Cada Lua de categoría llama de vuelta a subcomandos nuevos del script bash existente (ej. `archfrican-defaults __is-installed <how> <id>`, `archfrican-defaults __install <spec>`) en vez de reimplementar la detección de `pacman`/`flatpak`/AUR en Lua — el bash sigue siendo la única fuente de verdad de esa lógica. Las acciones de instalación usan `terminal = true`, igual que el flujo `ghostty -e sudo pacman ...` de hoy. La entrada "Control de versiones" simplemente ejecuta `archfrican-git` con `terminal = true` — sigue siendo un wizard de terminal aparte, no se intenta convertir. |
| `archfrican-setup` | Top-level TOML + submenús mixtos | `menus/setup.toml` + Lua solo donde hace falta (ej. `menus/setup-displays.lua` para la lista de monitores conectados en vivo); el resto de submenús (Apariencia, Red/VPN, Privacidad) son TOML estático | Mismo patrón que `defaults`: árbol de submenús en vez de reimplementar el loop `while :; do` actual. |

**Cambio de UX confirmado**: hoy `archfrican-actions`/`archfrican-setup` quedan abiertos entre selección y selección (loop hasta "Terminar"). Las versiones nativas **cierran tras cada selección**, igual que el resto de Walker — para elegir otra cosa hay que reabrir con el atajo. Se acepta este cambio de comportamiento a cambio de consistencia con el resto del launcher.

## Manejo de errores

- El chequeo del wrapper (`command -v walker && elephant listproviders | grep ...`) cubre el caso "Walker/elephant no responden" cayendo al fuzzel original — ningún atajo de la Fase 2 queda sin funcionar si el daemon se cae.
- Cada `GetEntries()` en Lua valida que `io.popen()` no devuelva `nil` antes de leer (mismo patrón usado en la prueba empírica de esta sesión) — un comando que falla produce 0 entradas, no un error que tumbe Walker.
- Los flujos de instalación (`defaults`) siguen corriendo con `terminal = true`, o sea con el error de `pacman`/`paru` visible en una terminal real, igual que hoy — sin regresión.
- Antes de eliminar cada script de la Fase 1, el paso de `grep` (ver arriba) evita romper alguna referencia no catalogada.

## Despliegue

Los archivos nuevos bajo `home/dot_config/elephant/menus/` se despliegan por chezmoi sin cambios de tooling. El único punto real: **elephant necesita reiniciarse para descubrir un archivo de menú nuevo** (confirmado empíricamente en esta sesión — con un archivo nuevo no aparece en `elephant listproviders` hasta reiniciar el proceso). Como `elephant` hoy se levanta con `spawn-at-startup "elephant"` sin unidad systemd, un `chezmoi apply` que agregue estos archivos no lo reinicia solo.

Se agrega ese restart a `home/run_after_99-apply-theme.sh.tmpl` — el mismo hook que ya restaura pantallas y tema después de cada `chezmoi apply` — para que quede automático en cada futuro `chezmoi apply`, sin pasos manuales y sin riesgo de que el menú "no aparezca" después de un cambio.

## Verificación / cómo se prueba

1. **Menú aislado, sin abrir UI**: `elephant query "menus:<nombre>;;10;false" --json` — permite revisar entradas exactas (texto, orden, valores) de forma scriptable, comparándolas contra la salida del script bash equivalente.
2. **Visual real**: `walker -m "menus:<nombre>"` — se prueba de forma interactiva, con el usuario presente (no se dispara sin avisar, porque abre una ventana real en su escritorio).
3. **Rama de fallback**: se simula "Walker/elephant ausente" deteniendo el proceso `elephant` un instante y confirmando que el wrapper cae correctamente a la lógica fuzzel original, sin tocar el sistema real más allá de ese instante.
4. **`niri validate`** sobre `config.kdl` después de cualquier cambio a `binds{}` (Fase 1), siguiendo la misma práctica ya usada en el trabajo anterior sobre este mismo archivo.
5. **Regresión Fase 1**: tras eliminar cada script, confirmar que el `grep` de referencias cruzadas (ver "Manejo de errores") dio limpio antes de borrar.
6. **Commits modulares**: cada script migrado (Fase 1: cada retiro; Fase 2: cada uno de los 5) se confirma funcionando de forma aislada antes de pasar al siguiente, con un commit de checkpoint por unidad — seguimos la práctica ya establecida en este repo de no acumular todo en un commit final.
