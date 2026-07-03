# Agregar KDE Plasma como sesión de escritorio opt-in, en paralelo a niri

## Contexto

niri (scrolling-tiling) es el núcleo de Archfrican y funciona muy bien para gente que ya
tiene experiencia con Linux — pero introduce fricción real para usuarios que recién
migran desde Windows: no hay barra de tareas tradicional, no hay menú inicio, no hay
ventanas superpuestas/flotantes por defecto, y el modelo de columnas scrolling no tiene
equivalente directo en la experiencia que ya conocen.

El pedido original fue "agregar X11 y Hyperland (Hyprland)". Al investigar, encontramos que
el proyecto ya evaluó y **rechazó explícitamente Hyprland** (`docs/CONTEXT.md`): preferencia
por niri por fiabilidad, para evitar el cambio de Hyprland 0.55 a Lua, y para evitar la
fragilidad de plugins tipo `hyprscroller`. X11 además ya tiene un fallback documentado de
una sola línea (`DisplayServer=x11` en `modules/20-niri-desktop.sh`), pero es específico
para el **greeter** de SDDM cuando una GPU no anda bien con Wayland — no una sesión de
escritorio X11 completa.

Conversando el objetivo real, quedó claro que ni X11 ni Hyprland eran el fin en sí mismos:
la necesidad es **una interfaz genuinamente familiar para gente que viene de Windows**,
seleccionable en el login, que el usuario pueda usar "cuando haga falta" sin afectar en
nada la experiencia de niri para quien ya la prefiere.

## Alcance

**Sí cubre:**
- Instalar **KDE Plasma** (shell mínimo, Wayland) como una sesión adicional, seleccionable
  en el desplegable de sesión de SDDM junto a niri.
- Un módulo opt-in nuevo (mismo patrón que gaming/SSH/multi-boot): se ofrece en el
  asistente de instalación, y también se puede instalar en cualquier momento después.
- Aplicar el tema visual de Archfrican (colores, wallpaper, iconos, cursor, fuentes) a
  Plasma también, para que ambas sesiones se sientan parte del mismo producto.
- Reutilizar apps que Archfrican ya instala (ghostty como terminal, gnome-software como
  tienda) en vez de duplicar todo el paquete de apps de KDE.

**Explícitamente fuera de alcance** (decisiones tomadas durante el brainstorming, no
descuidos):
- **X11 como sesión de escritorio completa.** Sigue existiendo solo el fallback de greeter
  ya documentado; no se agrega un WM de X11 (i3/bspwm/etc.).
- **Hyprland literal.** Se descarta a favor de Plasma por las razones ya documentadas en
  el proyecto (fiabilidad, Lua, plugins frágiles) — Plasma resuelve mejor el objetivo real
  (familiaridad con Windows) sin reabrir esa discusión.
- **Atajos/launcher de Archfrican dentro de Plasma.** Plasma usa su menú inicio (Kickoff) y
  gestión de ventanas nativos — no se inyecta Walker/fuzzel ni el esquema de atajos
  ⌘-estilo-macOS de niri. Esto es intencional: la familiaridad con Windows depende de usar
  los componentes nativos de Plasma, no los de Archfrican.
- **Suite completa de apps KDE** (Konsole, Kate, Discover). Se instala el shell mínimo +
  Dolphin (explorador de archivos, sin equivalente reusable) y se reutiliza el resto.
- **Resolver el conflicto de `keyd` con Win+L/Win+R dentro de Plasma** (ver más abajo) —
  documentado como limitación conocida, no bloquea este proyecto.

## Arquitectura

### Módulo nuevo, mismo patrón que los módulos opt-in existentes

- `packages/plasma-desktop.txt` — lista de paquetes mínima:
  `plasma-desktop`, `kwin`, `dolphin`, `kde-cli-tools` (trae `kwriteconfig6` /
  `plasma-apply-*`, necesarios para el theming), `plasma-nm` (applet de red nativo),
  `plasma-pa` (applet de audio nativo), `xdg-desktop-portal-kde` (screencast/file-picker
  correctos bajo Wayland). Nada de Konsole/Kate/Discover.
- `modules/25-plasma-desktop.sh` — instala la lista de paquetes. No toca absolutamente
  nada de niri/waybar/swaync/keyd. Sigue el mismo patrón de idempotencia con hash de
  contenido y stamp `.done` que el resto de los módulos (resumible, convergente).
- El paquete `plasma-desktop` de Arch ya trae su propio `.desktop` de sesión Wayland bajo
  `/usr/share/wayland-sessions/` — SDDM lo detecta automáticamente, igual que ya hace con
  niri. No hace falta ningún archivo de sesión propio de Archfrican.
- **Wizard**: una pregunta opt-in más en `lib/phase2.sh` (y `lib/phase1.sh` para el resumen
  de ISO), mismo patrón que gaming/SSH/multi-boot:
  `ui_confirm_default_no "Install KDE Plasma as an additional desktop session (Windows-familiar, opt-in)?"`
- **Re-ejecutable en cualquier momento**: `~/.archfrican/install.sh 25-plasma-desktop yes`,
  igual que cualquier otro módulo — así se puede agregar después de la instalación inicial,
  sin tener que haberlo elegido en el asistente.

### Theming: paso nuevo, best-effort, en `bin/theme-switch`

Se agrega un bloque nuevo al final de `theme-switch` (mismo patrón que el bloque
best-effort de SDDM ya existente — guardado con `have`/`command -v`, nunca falla si
Plasma no está instalado):

- Wallpaper: `plasma-apply-wallpaperimage <ruta>` con la misma imagen que ya usa
  `archfrican-wallpaper`/`archfrican-wallpaper-restore` (o el color plano del tema activo
  si no hay imagen elegida).
- Esquema de color: generado a partir de los mismos `BG`/`FG`/`ACCENT` del tema activo
  (`colors.sh`), aplicado vía `plasma-apply-colorscheme` o escrito directo a `kdeglobals`
  con `kwriteconfig6`.
- Tema de iconos (WhiteSur) y cursor (McMojave) — ya instalados para GTK, se reutilizan.
- Fuentes (Inter / JetBrainsMono) — mismas que el resto del sistema.

Efecto: cambiar de tema desde niri (o desde dentro de Plasma) deja ambas sesiones
coherentes la próxima vez que se entra a cualquiera de las dos.

### Apps y atajos dentro de Plasma

- Menú inicio, barra de tareas, gestión de ventanas (flotante + snap): **nativos de
  Plasma**, sin modificaciones.
- Terminal por defecto: **ghostty** (se configura como app por defecto en los ajustes de
  Plasma vía `kwriteconfig6`), para no duplicar Konsole.
- Explorador de archivos: **Dolphin** (nuevo — Nautilus no está pensado para integrarse
  con Plasma).
- Tienda de apps: se reutiliza **gnome-software** (ya instalado); no se agrega Discover.

### Limitación conocida (documentada, no resuelta en este proyecto)

`keyd` remapea `⌘+L`→`Ctrl+L` y `⌘+R`→`Ctrl+R` a nivel de todo el sistema (input-level,
no es específico de niri). Dentro de Plasma, un usuario que pruebe **Win+L** (bloquear) o
**Win+R** (ejecutar) — atajos esperables viniendo de Windows — no van a funcionar como
esperan, porque keyd los intercepta antes de que Plasma los vea. Resolverlo bien
requeriría que keyd supiera qué sesión/compositor está activa, lo cual es un proyecto
aparte con más alcance. Se documenta acá como limitación conocida.

## Manejo de errores

- El módulo sigue el mismo mecanismo de resiliencia que el resto (`resilient_enable`,
  `best_effort` donde corresponda, hash-stamp para reintentos seguros).
- El paso de theming para Plasma es 100% best-effort: si Plasma no está instalado, es un
  no-op silencioso — cero riesgo para quien solo usa niri.

## Testing / validación

- `bash -n` + shellcheck sobre el módulo nuevo — ya cubierto por los globs existentes de
  CI (`modules/*.sh`), sin necesitar workflows nuevos.
- El paso de theming para Plasma se ejerce en CI automáticamente por el hecho de que los
  runners de CI **no** tienen Plasma instalado — así el camino "no-op cuando falta"
  (el más importante de garantizar) queda probado gratis en cada corrida del
  `theme-switch-smoke` job existente.
- Validación en vivo (manual, en esta máquina): instalar el módulo, confirmar que
  "Plasma" aparece en el selector de sesión de SDDM, entrar, confirmar tema/wallpaper
  aplicados, confirmar que niri sigue funcionando exactamente igual que antes.
