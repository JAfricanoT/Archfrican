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
de Material Design Icons ("overcast": U+F0590) con el resto de sus propios íconos que sí son del
subset Weather Icons, y tres indicadores de estado (conectividad a internet, privacidad,
notificaciones) usan un simple `●` (U+25CF) de texto plano — elegido a propósito en su momento para
no depender de Nerd Font. Como Nerd Font (`ttf-jetbrains-mono-nerd`) ya es una dependencia
obligatoria del tema, esa razón ya no aplica y se puede unificar todo a la misma fuente/familia.

**Hallazgo adicional (verificado con `fontTools` contra el bash del script, no de memoria):**
`archfrican-weather` tiene roto TODO su mapa de íconos salvo "overcast" — un `hexdump` del archivo
confirma que las 15 claves restantes (`sunny`, `clear`, `partly`, `cloud`, `rain`, `drizzle`,
`shower`, `snow`, `blizzard`, `sleet`, `thunder`, `lightning`, `mist`, `fog`, `haze`) valen
literalmente `""` — ningún glifo, no una mezcla de estilos. En la práctica el clima nunca muestra
ícono salvo cuando la condición es exactamente "overcast". Como este plan ya toca ese mismo
diccionario para reemplazar el glifo de "overcast", se suma restaurar los 15 glifos faltantes en la
misma tarea — dejar 15 de 16 en blanco mientras se "unifica" el que sí tiene glifo no tendría
sentido.

## Alcance

**Sí cubre:**
- Reagrupar `modules-right` en 4 elementos en vez de 14: el módulo `pulseaudio` (ahora solo ícono)
  + tres módulos `group` nativos de Waybar (`group/system`, `group/connectivity`, `group/status`),
  cada uno agrupando los módulos ya existentes sin tocar la lógica de ninguno.
- Mantener una sola isla exterior (mismo contenedor visual de hoy) — la separación entre grupos es
  un divisor fino en el contenedor del `group`, no una isla flotante nueva por grupo.
- Volumen: el módulo `pulseaudio` deja de mostrar `{volume}%` en la barra; el ícono queda solo, y el
  porcentaje + dispositivo activo aparecen en el tooltip nativo al pasar el mouse (mismo patrón que
  ya usa `disk`: ícono+libre en la barra, detalle completo en el tooltip). Se agrega un ícono
  distinto para el estado silenciado (`format-muted`), ya que al ocultar el %, el ícono pasa a ser
  la única señal a simple vista de que está muteado.
- Unificar la fuente de íconos: `font-family: "JetBrainsMono Nerd Font"` explícito en todo elemento
  que renderiza un glifo (no depender del fallback de la cadena de fuentes declarada en `*`).
- Restaurar los 16 glifos de `archfrican-weather` (incluyendo el reemplazo de "overcast") con
  glifos del subset Weather Icons de Nerd Font — todos verificados contra la fuente real instalada
  (`JetBrainsMonoNerdFont-Regular.ttf`) con `fontTools`, ningún codepoint de memoria. Ver
  Arquitectura para la tabla completa.
- Convertir los 3 indicadores `●` de texto plano (conectividad, privacidad, notificaciones) a
  `fa-circle` (U+F111, Nerd Font subset Font Awesome — mismo que domina el resto de la barra),
  tanto en `config.jsonc` (`custom/notification`) como en los dos scripts que emiten el suyo propio
  (`archfrican-net-status`, `archfrican-privacy-indicator`).

**Agrupamiento exacto:**
- `group/system`: `cpu`, `memory`, `disk`, `power-profiles-daemon`, `battery`
- `group/connectivity`: `network`, `bluetooth`, `custom/connectivity`
- `group/status`: `custom/health`, `custom/notification`, `custom/caffeine`, `custom/privacy`,
  `tray`
- `pulseaudio` queda fuera de los 3 grupos, como elemento independiente (el más "oculto" de todos).

**Corrección post-verificación:** el grupo de red se llama `group/connectivity`, no `group/network`
como se planteó originalmente durante el brainstorming. Motivo: Waybar asigna a un módulo
`"group/<nombre>"` el id de CSS `#<nombre>` (sin el prefijo `group-`, confirmado contra la wiki
oficial y el issue [Alexays/waybar#4378](https://github.com/Alexays/waybar/issues/4378), que
documenta exactamente esta colisión). `group/network` habría generado `#network` — el MISMO id que
ya usa el módulo `network` que vive adentro de ese propio grupo, rompiendo el CSS de ambos.
`group/connectivity` no colisiona con ningún id existente.

**Explícitamente fuera de alcance** (decisiones tomadas durante el brainstorming):
- **Ninguna animación tipo "drawer"/popup flotante para el volumen.** Se evaluó (mostrar el % con
  una transición al hacer clic, o un popup GTK con slider) pero se descartó a favor del tooltip
  nativo — mismo patrón ya usado por `disk`, cero código/mecanismo nuevo.
- **Los 3 puntos de estado NO se separan en su propio grupo.** Cada uno vive en el grupo temático al
  que ya pertenece hoy (conectividad → `group/connectivity`; privacidad, notificaciones →
  `group/status`).
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
"modules-right": ["pulseaudio", "group/system", "group/connectivity", "group/status"],

"group/system": {
  "orientation": "horizontal",
  "modules": ["cpu", "memory", "disk", "power-profiles-daemon", "battery"]
},
"group/connectivity": {
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
comportamiento. `"orientation": "horizontal"` es explícito en los tres (no depender del default
`orthogonal` documentado en `man 5 waybar`, aunque en una barra horizontal como esta coincidiría).

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
`format-muted` usa U+EEE8 (`fa-volume_xmark`), un glifo Font Awesome propio para "silenciado",
distinto del que ya usa el nivel más bajo del array `default` (U+F026, `fa-volume_off`, reutilizado
ahí para "volumen casi en cero" — no se toca ese mapeo existente). Ambos códigos confirmados
presentes en `JetBrainsMonoNerdFont-Regular.ttf` con `fontTools`. El scroll para subir/bajar volumen
sobre el módulo ya es comportamiento nativo de `pulseaudio` (`man 5 waybar-pulseaudio`) — no
requiere config nueva.

`custom/notification` cambia sus 4 ocurrencias de `"●"` por el glifo U+F111 (`fa-circle`).

**Nota de método — no tipear los glifos literalmente:** al escribir este mismo documento, cada
intento de pegar el carácter Nerd Font real (Private Use Area / planos suplementarios: U+E30D,
U+F111, U+EEE8, etc.) directamente en el texto terminó guardándose como string vacío — confirmado
con `cat -A` y un `hexdump`. Caracteres BMP comunes (`●` U+25CF, `—` U+2014) sí sobreviven; los
glifos de ícono no. Esto explica el bug de `archfrican-weather` descrito arriba (alguien escribió
esos glifos "a mano" y quedaron vacíos sin que se notara). La implementación NO debe repetir ese
error — el método concreto por tipo de archivo:
- **`archfrican-weather` (Python):** escapes `"\UXXXXXXXX"` directo en el código fuente (ver bloque
  de arriba) — Python los decodifica solo en tiempo de ejecución, el archivo en disco queda en ASCII
  puro para siempre.
- **`archfrican-net-status` / `archfrican-privacy-indicator` (bash):** mismo patrón ya usado en
  `archfrican-caffeine` (`ICON_OFF=$'\xef\x86\x86'   # nf-fa-moon-o U+F186`) — bytes UTF-8 crudos
  vía `$'\xHH\xHH\xHH'`, no el escape `\u` de bash (evita depender del locale). Para U+F111
  (`fa-circle`): `$'\xef\x84\x91'`.
- **`config.jsonc`:** el archivo ya usa bytes UTF-8 crudos para todos sus íconos existentes (no
  escapes `\u` de JSON) — para mantener el mismo estilo, el/la implementador genera el byte real con
  un script Python de una línea (`open(...).read().replace(...)` usando `"\UXXXXXXXX"` como
  reemplazo, luego `open(...,"w").write(...)`), nunca pegando el carácter en un editor.
- **Verificación obligatoria en cada paso que inserta un glifo:** releer el archivo y comparar
  `hex(ord(char))` contra el codepoint esperado (mismo método usado para redactar esta spec) — nunca
  confiar en que "se ve bien" a simple vista.

### `home/dot_local/bin/executable_archfrican-weather`

El diccionario `ICONS` completo (16 claves — 15 vacías hoy + "overcast" con el glifo Material
Design a reemplazar) pasa a construirse con escapes `\U` en vez de glifos literales (ver Nota de
método más abajo), por ejemplo:

```python
ICONS = {
    "sunny": "\U0000E30D", "clear": "\U0000E32B", "partly": "\U0000E302",
    "cloud": "\U0000E33D", "overcast": "\U0000E312",
    "rain": "\U0000E318", "drizzle": "\U0000E31B", "shower": "\U0000E319",
    "snow": "\U0000E31A", "blizzard": "\U0000E35E", "sleet": "\U0000E3AD",
    "thunder": "\U0000E31D", "lightning": "\U0000E315",
    "mist": "\U0000E313", "fog": "\U0000E313", "haze": "\U0000E3AE",
}
```
Todos los glifos Weather Icons confirmados presentes en `JetBrainsMonoNerdFont-Regular.ttf` con
`fontTools`, por nombre real (no adivinados):

| clave | glifo real | codepoint |
|---|---|---|
| sunny | `weather-day_sunny` | U+E30D |
| clear | `weather-night_clear` | U+E32B |
| partly | `weather-day_cloudy` | U+E302 |
| cloud | `weather-cloud` | U+E33D |
| overcast | `weather-cloudy` | U+E312 |
| rain | `weather-rain` | U+E318 |
| drizzle | `weather-sprinkle` | U+E31B |
| shower | `weather-showers` | U+E319 |
| snow | `weather-snow` | U+E31A |
| blizzard | `weather-snow_wind` | U+E35E |
| sleet | `weather-sleet` | U+E3AD |
| thunder | `weather-thunderstorm` | U+E31D |
| lightning | `weather-lightning` | U+E315 |
| mist | `weather-fog` | U+E313 |
| fog | `weather-fog` | U+E313 (mismo glifo que `mist` — Weather Icons no distingue las dos condiciones) |
| haze | `weather-day_haze` | U+E3AE |

### `home/dot_config/waybar/style.css`

- El selector `*` que ya declara `font-family: "Inter", "JetBrainsMono Nerd Font", sans-serif`
  gana una regla más específica para los elementos que son puramente ícono (todo lo que hoy tiene
  un glifo Nerd Font en su `format`), forzando `"JetBrainsMono Nerd Font"` sin fallback — así el
  glifo nunca puede terminar renderizado por Inter/sans-serif por accidente.
- Los tres `#system`, `#connectivity`, `#status` — Waybar asigna a un módulo `"group/<nombre>"` el
  id de CSS `#<nombre>` (sin prefijo `group-`; confirmado contra la wiki oficial de Waybar y
  [Alexays/waybar#4378](https://github.com/Alexays/waybar/issues/4378)) — reciben el mismo
  fondo/padding que hoy tiene `.modules-right` por módulo individual, más un `border-right` fino
  (mismo valor ya usado por
  `.modules-center #custom-weather { border-right: 1px solid alpha(@fg_dim, 0.20); }`). El mockup
  aprobado durante el brainstorming mostraba 4 secciones separadas por divisor (volumen · sistema ·
  conectividad · estado), así que `#pulseaudio` también recibe ese mismo `border-right` — el único
  que NO lo lleva es `#status` (el último, pegado al borde de la isla).
- Los estilos existentes por-módulo (`#cpu`, `#memory`, `#disk`, etc. y sus reglas `:hover`) no se
  tocan — siguen aplicando igual dentro de su `group`.

### Scripts afectados (fuera de `waybar/`)

- `home/dot_local/bin/executable_archfrican-net-status`: sus 3 `printf` (`offline`, `unstable`,
  `online`) cambian `"text":"●"` al glifo U+F111 (`fa-circle`) — mismo glifo que el resto de los
  indicadores de estado.
- `home/dot_local/bin/executable_archfrican-privacy-indicator`: su único `printf` con `"text":"●"`
  cambia igual.

## Manejo de errores

- Todos los codepoints y el nombre del selector CSS que este documento necesitaba (glifo de
  "overcast" y los 15 restantes de `archfrican-weather`, el círculo de unificación, el ícono de
  volumen silenciado, y el id de CSS que genera Waybar para un módulo `group/<nombre>`) ya están
  verificados empíricamente arriba — contra la fuente `JetBrainsMonoNerdFont-Regular.ttf`
  realmente instalada (vía `fontTools`) y contra la documentación oficial de Waybar
  (`man 5 waybar`, wiki, issue #4378) — no hay valores pendientes de confirmar durante la
  implementación.
- Si un módulo dentro de un `group` se auto-oculta (p.ej. `custom/privacy` cuando no hay
  mic/cámara en uso), el `group` como contenedor no colapsa a cero automáticamente por defecto en
  Waybar; si el resultado visual deja un hueco notorio, ajustar el CSS del grupo (no la lógica del
  módulo) es la superficie correcta para resolverlo.
- No hay forma de probar JSONC/CSS de layout con un test automatizado en este repo (no hay
  precedente de CI para `waybar/`). La validación es: sintaxis JSON válida (stripeando comentarios)
  + verificación visual en vivo reiniciando waybar dentro de niri.

## Testing / validación

- Validar que `config.jsonc` siga siendo JSON válido después de sacarle los comentarios `//`
  (`grep -v '^\s*//' config.jsonc | jq .` o equivalente).
- Verificar en vivo: reiniciar waybar (`pkill waybar` — se relanza solo por el `systemd`
  `waybar.service` ya existente, o `Mod+Shift+H` si solo hace falta togglear visibilidad) y
  confirmar:
  - Se ven 4 secciones (volumen · sistema · conectividad · estado) separadas por un divisor fino,
    dentro de la misma isla — no 3 islas flotantes independientes.
  - El volumen no muestra `%` en la barra; pasar el mouse muestra el tooltip con el % correcto;
    mutear muestra el ícono de `format-muted`.
  - Todos los glifos (batería, red, bluetooth, cpu, memoria, disco, perfil de energía, cafeína,
    salud, clima, y los 3 puntos de estado) se ven con el mismo peso/estilo visual — ningún
    cuadrado "tofu" (glifo faltante) ni mezcla de estilos evidente.
  - Ningún módulo perdió información respecto a hoy (todo lo que se veía en texto sigue disponible,
    ya sea en la barra o en el tooltip).
