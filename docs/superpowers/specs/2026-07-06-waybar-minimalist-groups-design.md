# Redistribuir la waybar en grupos internos + unificar la fuente de íconos

## Contexto

Hoy `modules-right` en `home/dot_config/waybar/config.jsonc` apila 14 módulos sueltos
(`custom/privacy`, `pulseaudio`, `bluetooth`, `custom/connectivity`, `network`, `cpu`, `memory`,
`disk`, `power-profiles-daemon`, `battery`, `custom/caffeine`, `custom/health`,
`custom/notification`, `tray`) dentro de una sola isla flotante. Visualmente se ve saturado — todo
del mismo tamaño, mismo fondo, sin jerarquía — aunque toda la información ahí es información que el
usuario efectivamente revisa (excepto el volumen, que rara vez necesita ver el número, solo ajustar
cuando hace falta).

Además, los íconos mezclan estilos: la mayoría sale de Nerd Font (subset Font Awesome — batería,
red, bluetooth, cpu, memoria, disco, perfil de energía, cafeína, salud), el clima mezcla un glifo
de Material Design Icons ("overcast": `󰖐`) con el resto de sus propios íconos que sí son del subset
Weather Icons, y tres indicadores de estado (conectividad a internet, privacidad, notificaciones)
usan un simple `●` de texto plano — elegido a propósito en su momento para no depender de Nerd
Font. Como Nerd Font (`ttf-jetbrains-mono-nerd`) ya es una dependencia obligatoria del tema, esa
razón ya no aplica y se puede unificar todo a la misma fuente/familia.

## Alcance

**Sí cubre:**
- Reagrupar `modules-right` en 4 elementos en vez de 14: el módulo `pulseaudio` (ahora solo ícono)
  + tres módulos `group` nativos de Waybar (`group/system`, `group/network`, `group/status`), cada
  uno agrupando los módulos ya existentes sin tocar la lógica de ninguno.
- Mantener una sola isla exterior (mismo contenedor visual de hoy) — la separación entre grupos es
  un divisor fino en el contenedor del `group`, no una isla flotante nueva por grupo.
- Volumen: el módulo `pulseaudio` deja de mostrar `{volume}%` en la barra; el ícono queda solo, y el
  porcentaje + dispositivo activo aparecen en el tooltip nativo al pasar el mouse (mismo patrón que
  ya usa `disk`: ícono+libre en la barra, detalle completo en el tooltip). Se agrega un ícono
  distinto para el estado silenciado (`format-muted`), ya que al ocultar el %, el ícono pasa a ser
  la única señal a simple vista de que está muteado.
- Unificar la fuente de íconos: `font-family: "JetBrainsMono Nerd Font"` explícito en todo elemento
  que renderiza un glifo (no depender del fallback de la cadena de fuentes declarada en `*`).
- Reemplazar el glifo "overcast" del clima (Material Design Icons) por uno del mismo subset Weather
  Icons que ya usa el resto de `archfrican-weather` — el codepoint exacto se confirma empíricamente
  durante la implementación (ver Manejo de errores), no se adivina acá.
- Convertir los 3 indicadores `●` de texto plano (conectividad, privacidad, notificaciones) a un
  glifo de círculo de Nerd Font (subset Font Awesome, mismo que domina el resto de la barra), tanto
  en `config.jsonc` (`custom/notification`) como en los dos scripts que emiten el suyo propio
  (`archfrican-net-status`, `archfrican-privacy-indicator`).

**Agrupamiento exacto:**
- `group/system`: `cpu`, `memory`, `disk`, `power-profiles-daemon`, `battery`
- `group/network`: `network`, `bluetooth`, `custom/connectivity`
- `group/status`: `custom/health`, `custom/notification`, `custom/caffeine`, `custom/privacy`,
  `tray`
- `pulseaudio` queda fuera de los 3 grupos, como elemento independiente (el más "oculto" de todos).

**Explícitamente fuera de alcance** (decisiones tomadas durante el brainstorming):
- **Ninguna animación tipo "drawer"/popup flotante para el volumen.** Se evaluó (mostrar el % con
  una transición al hacer clic, o un popup GTK con slider) pero se descartó a favor del tooltip
  nativo — mismo patrón ya usado por `disk`, cero código/mecanismo nuevo.
- **Los 3 puntos de estado NO se separan en su propio grupo.** Cada uno vive en el grupo temático al
  que ya pertenece hoy (conectividad → `group/network`; privacidad, notificaciones → `group/status`).
- **Ningún módulo se elimina ni pierde información.** Todo lo que hoy se ve en la barra (excepto el
  `{volume}%` inline, que pasa al tooltip) sigue visible exactamente igual; el cambio es puramente
  de agrupamiento visual y de fuente.
- **No se toca `modules-left` ni `modules-center`** (workspaces, título de ventana, clima, reloj) —
  el pedido fue específicamente sobre el lado derecho.

## Arquitectura

### `home/dot_config/waybar/config.jsonc`

`modules-right` pasa de:
```jsonc
"modules-right": [
  "custom/privacy",
  "pulseaudio", "bluetooth", "custom/connectivity", "network",
  "cpu", "memory", "disk",
  "power-profiles-daemon", "battery",
  "custom/caffeine", "custom/health", "custom/notification", "tray"
],
```
a:
```jsonc
"modules-right": ["pulseaudio", "group/system", "group/network", "group/status"],

"group/system": {
  "orientation": "horizontal",
  "modules": ["cpu", "memory", "disk", "power-profiles-daemon", "battery"]
},
"group/network": {
  "orientation": "horizontal",
  "modules": ["network", "bluetooth", "custom/connectivity"]
},
"group/status": {
  "orientation": "horizontal",
  "modules": ["custom/health", "custom/notification", "custom/caffeine", "custom/privacy", "tray"]
},
```

Los módulos individuales (`cpu`, `memory`, `disk`, etc.) mantienen exactamente su configuración
actual (`format`, `on-click`, `tooltip-format`, etc.) — el `group` solo los envuelve, no cambia su
comportamiento.

`pulseaudio` cambia de:
```jsonc
"pulseaudio": {
  "format": "{icon}  {volume}%",
  "format-icons": { "default": ["", "", ""] },
  "on-click": "pavucontrol"
},
```
a:
```jsonc
"pulseaudio": {
  "format": "{icon}",
  "format-muted": "",
  "format-icons": { "default": ["", "", ""] },
  "tooltip-format": "{volume}% — {desc}",
  "on-click": "pavucontrol"
},
```
(el glifo exacto de `format-muted` se confirma empíricamente contra la fuente instalada — ver
Manejo de errores.)

`custom/notification` cambia sus 4 ocurrencias de `"●"` por el glifo de círculo elegido para toda
la barra (mismo que reemplaza los `●` de los dos scripts bash).

### `home/dot_config/waybar/style.css`

- El selector `*` que ya declara `font-family: "Inter", "JetBrainsMono Nerd Font", sans-serif`
  gana una regla más específica para los elementos que son puramente ícono (todo lo que hoy tiene
  un glifo Nerd Font en su `format`), forzando `"JetBrainsMono Nerd Font"` sin fallback — así el
  glifo nunca puede terminar renderizado por Inter/sans-serif por accidente.
- Los tres `#group-system`, `#group-network`, `#group-status` (nombre exacto del selector CSS que
  Waybar genera para un módulo `"group/<nombre>"` — se confirma contra la versión de Waybar
  instalada, no se asume) reciben el mismo fondo/padding que hoy tiene `.modules-right` por módulo
  individual, más un `border-right` fino (mismo valor ya usado por
  `.modules-center #custom-weather { border-right: 1px solid alpha(@fg_dim, 0.20); }`). El mockup
  aprobado durante el brainstorming mostraba 4 secciones separadas por divisor (volumen · sistema ·
  red · estado), así que el `#pulseaudio` también recibe ese mismo `border-right` — el único que
  NO lo lleva es `#group-status` (el último, pegado al borde de la isla).
- Los estilos existentes por-módulo (`#cpu`, `#memory`, `#disk`, etc. y sus reglas `:hover`) no se
  tocan — siguen aplicando igual dentro de su `group`.

### Scripts afectados (fuera de `waybar/`)

- `home/dot_local/bin/executable_archfrican-net-status`: sus 3 `printf` (`offline`, `unstable`,
  `online`) cambian `"text":"●"` al mismo glifo Nerd Font elegido para los indicadores de estado.
- `home/dot_local/bin/executable_archfrican-privacy-indicator`: su único `printf` con `"text":"●"`
  cambia igual.

## Manejo de errores

- **Codepoints exactos a confirmar en vivo, no adivinar** (mismo criterio que ya usa este repo,
  p.ej. el TODO de `kdeglobals` en `modules/25-plasma-desktop.sh`):
  1. El glifo de reemplazo para "overcast" en `archfrican-weather` (Weather Icons, no Material
     Design Icons).
  2. El glifo del círculo elegido para unificar `●` → Nerd Font, y el de `format-muted` del
     volumen — ambos deben confirmarse renderizables contra la fuente instalada
     (`ttf-jetbrains-mono-nerd`) antes de darlos por buenos.
  3. El selector CSS exacto que genera Waybar para un módulo `"group/<nombre>"` (`#<nombre>` vs
     `#group-<nombre>` vs otro) — se confirma contra Waybar 0.15.0 (versión ya instalada en esta
     máquina) antes de escribir el CSS final.
- Si un módulo dentro de un `group` se auto-oculta (p.ej. `custom/privacy` cuando no hay
  mic/cámara en uso, o `custom/weather` — que no está en este alcance, pero como referencia de
  patrón), el `group` como contenedor no colapsa a cero automáticamente por defecto en Waybar; si
  el resultado visual deja un hueco notorio, ajustar el CSS del grupo (no la lógica del módulo) es
  la superficie correcta para resolverlo.
- No hay forma de probar JSONC/CSS de layout con un test automatizado en este repo (no hay
  precedente de CI para `waybar/`). La validación es: sintaxis JSON válida (stripeando comentarios)
  + verificación visual en vivo reiniciando waybar dentro de niri.

## Testing / validación

- Validar que `config.jsonc` siga siendo JSON válido después de sacarle los comentarios `//`
  (`grep -v '^\s*//' config.jsonc | jq .` o equivalente).
- Verificar en vivo: reiniciar waybar (`pkill waybar` — se relanza solo por el `systemd`
  `waybar.service` ya existente, o `Mod+Shift+H` si solo hace falta togglear visibilidad) y
  confirmar:
  - Se ven 4 secciones (volumen · sistema · red · estado) separadas por un divisor fino, dentro de
    la misma isla — no 3 islas flotantes independientes.
  - El volumen no muestra `%` en la barra; pasar el mouse muestra el tooltip con el % correcto;
    mutear muestra el ícono de `format-muted`.
  - Todos los glifos (batería, red, bluetooth, cpu, memoria, disco, perfil de energía, cafeína,
    salud, clima, y los 3 puntos de estado) se ven con el mismo peso/estilo visual — ningún
    cuadrado "tofu" (glifo faltante) ni mezcla de estilos evidente.
  - Ningún módulo perdió información respecto a hoy (todo lo que se veía en texto sigue disponible,
    ya sea en la barra o en el tooltip).
