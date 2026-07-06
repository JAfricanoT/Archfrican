# Botón de energía/sistema en waybar

## Contexto

Hoy no existe ningún punto de entrada para bloquear/cerrar sesión/suspender/reiniciar/apagar desde
la waybar. Lo que sí existe:

- `archfrican-lock` — el único punto de entrada de bloqueo de pantalla (idle, antes de dormir,
  `Mod+Shift+L`).
- `Mod+Shift+E { quit; }` en `home/dot_config/niri/config.kdl.tmpl:160` — cierra la sesión de niri
  directo desde el compositor (KDL nativo), pero sin equivalente en ningún menú.
- `archfrican-actions` (`Mod+Shift+A`) — el "centro de control" ya existente: un menú largo con
  Asistente de configuración, Atajos de teclado, tema, apps por defecto, etc. Usa el proveedor
  nativo de Walker (`menus:actions`, respaldado por
  `home/dot_config/elephant/menus/actions.toml.tmpl`) cuando Walker/elephant están corriendo, y cae
  a una lista `fuzzel --dmenu` si no. **No tiene ninguna acción de energía.**
- `archfrican-power` (nombre ya ocupado) — selector de perfil de energía/TLP/thermald, no tiene
  relación con apagar/reiniciar.
- `archfrican-rollback` — ya usa el patrón "segundo dmenu de confirmación antes de un `sudo
  systemctl reboot`" que este spec reutiliza.

`niri msg action --help` confirma que `quit` es una acción válida del IPC de niri (mismo efecto
que el `quit;` ya usado en el keybind).

## Alcance

**Sí cubre:**
- Agregar 5 acciones nuevas al menú de control YA EXISTENTE (`archfrican-actions` /
  `menus:actions`): Bloquear pantalla, Cerrar sesión, Suspender, Reiniciar, Apagar.
- Un botón nuevo en waybar (`custom/power`, extremo derecho, después de `tray`) cuyo `on-click`
  invoca `archfrican-actions` — el script decide internamente Walker nativo vs. fallback fuzzel,
  la waybar no necesita saberlo.
- Confirmación ("¿Seguro? Sí/No", mismo patrón que `archfrican-rollback`) antes de Reiniciar,
  Apagar o Cerrar sesión — son las tres que pueden perder trabajo sin guardar.

**Explícitamente fuera de alcance** (decisiones tomadas durante el brainstorming):
- **Ningún menú nuevo y separado.** Se evaluó crear un script `archfrican-powermenu` dedicado, pero
  se descartó: `archfrican-actions` ya es el centro de control con acceso por teclado
  (`Mod+Shift+A`) y ya cubre "configuraciones"/"atajos" que el usuario pidió junto con las opciones
  de energía — un segundo menú paralelo duplicaría lógica sin necesidad.
- **Sin wlogout ni menú visual de botones grandes.** Se evaluó como alternativa más "parecida a un
  SO de escritorio", pero se descartó a favor de mantener consistencia con el resto del repo
  (todos los menús de acción — `archfrican-power`, `archfrican-session`, el propio
  `archfrican-actions` — usan listas dmenu con teclado, no grids visuales) y evitar una
  dependencia nueva.
- **Sin `sudo` en los comandos de energía.** `systemctl suspend/reboot/poweroff` para el usuario en
  la sesión activa ya están autorizados por defecto vía polkit/systemd-logind (igual que en
  GNOME/KDE) — pedir contraseña rompería el flujo de un botón de un clic. Es una diferencia
  deliberada frente al `sudo systemctl reboot` que usa `lib/phase2.sh`/`archfrican-rollback`,
  porque esos corren en contextos sin sesión de escritorio activa (instalador, o después de un
  rollback donde no se puede asumir polkit configurado).
- **Sin confirmación en Bloquear ni Suspender** — son reversibles/inofensivos, agregar un paso
  extra ahí sería fricción sin beneficio.

## Arquitectura

### Los 5 ítems nuevos

Van al **principio** de la lista/TOML en ambos frontends (visibilidad al abrir el menú con mouse,
antes de escribir nada para filtrar):

| Texto | Comando | Confirma |
|---|---|---|
| Bloquear pantalla | `archfrican-lock` | No |
| Cerrar sesión | `niri msg action quit` | Sí |
| Suspender | `systemctl suspend` | No |
| Reiniciar | `systemctl reboot` | Sí |
| Apagar | `systemctl poweroff` | Sí |

### Dos frontends, deben quedar sincronizados

El mismo menú lógico vive en dos archivos hoy (uno es el fallback del otro) — este spec toca
ambos para que no diverjan:

1. **`home/dot_local/bin/executable_archfrican-actions`** (fallback fuzzel): 5 líneas nuevas al
   `printf` inicial (antes de la primera opción actual) + 5 `case` branches nuevos. El branch de
   Reiniciar/Apagar/Cerrar sesión hace un segundo `fuzzel --dmenu` de confirmación antes de
   ejecutar, mismo patrón que `archfrican-rollback:25`.
2. **`home/dot_config/elephant/menus/actions.toml.tmpl`** (proveedor nativo de Walker — el que
   realmente se ve día a día cuando Walker/elephant están corriendo): 5 `[[entries]]` nuevas al
   principio del archivo. La confirmación ahí se resuelve con `run = "sh -c '... confirm via
   fuzzel/walker --dmenu ...'"` inline, igual estilo que las entries existentes que ya envuelven
   lógica de shell (p.ej. "Buscar actualizaciones").

### Waybar

Nuevo módulo en `home/dot_config/waybar/config.jsonc`, agregado al final de `modules-right`
(después de `"tray"`):

```jsonc
"custom/power": {
  "format": "",
  "tooltip-format": "Energía / sistema",
  "on-click": "$HOME/.local/bin/archfrican-actions"
}
```

Sin `interval`/`exec` — es un botón estático (icono fijo), no un módulo con estado que haga
polling, igual que otros botones de acción pura ya en el bar (aunque hoy todos los `custom/*`
existentes tienen `exec`; este es el primer botón puramente de acción, sin estado que reportar).

## Manejo de errores

- Si `archfrican-lock` no encuentra `gtklock`/`swaylock` instalados, ya falla con su propio
  mensaje (`exit 1`) — sin cambios, este spec no toca ese script.
- Si `niri msg action quit` se invoca fuera de una sesión de niri (no debería pasar nunca desde
  este menú, que solo es alcanzable dentro de niri), el comando de niri ya falla por su cuenta con
  un error de socket — no hace falta guarda adicional.
- `systemctl suspend/reboot/poweroff` sin permisos de polkit (caso raro, p.ej. una política de
  polkit personalizada más restrictiva): el comando falla con su propio mensaje de
  "Interactive authentication required" — no se agrega manejo especial, es el comportamiento
  esperado que cualquier DE tendría en ese caso.

## Testing / validación

- `bash -n` sobre `home/dot_local/bin/executable_archfrican-actions` tras el cambio.
- Verificar en vivo: `Mod+Shift+A` (o click en el nuevo botón de waybar) muestra las 5 opciones
  nuevas al principio de la lista, en ambos frontends (con Walker corriendo, y forzando el fallback
  fuzzel para probar el otro camino).
- Confirmar que Reiniciar/Apagar/Cerrar sesión piden confirmación y que elegir "No" no ejecuta
  nada.
- Confirmar que Suspender y Bloquear pantalla ejecutan directo, sin paso de confirmación.
- Confirmar que el nuevo botón de waybar aparece en el extremo derecho tras `theme-switch`/reinicio
  de waybar, y que el click abre el mismo menú que `Mod+Shift+A`.
