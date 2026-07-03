# Bundle curated Archfrican wallpapers, selectable at install and afterward

## Contexto

Hoy Archfrican no incluye ninguna imagen de fondo propia: si el usuario nunca elige una con
`archfrican-wallpaper`, `archfrican-wallpaper-restore` cae a un color sólido tomado del tema
activo (`#1c1c1e` en `archfrican-dark`, por ejemplo) — nunca queda en negro puro, pero tampoco
hay una identidad visual de marca en el fondo.

El usuario proveyó 5 imágenes propias (`/home/jafricanot/Downloads/Archfrican-{Blue,Cross,Cube,
CubeTwo,Curve}.jpg`, 3840×2160 a 8000×4500, JPEG). Las cinco comparten una misma familia visual:
abstractas, fondo oscuro/negro, vidrio y prismas 3D con el mismo azul de acento del sistema
(`#0a84ff`) que ya usa todo el tema — encajan directamente con la identidad "macOS-grade" que el
proyecto ya declara en `docs/DESIGN-LANGUAGE.md`. Ninguna es de paleta clara, así que son
candidatas naturales para los temas oscuros (no se fuerza ningún mapeo tema-por-tema todavía).

## Alcance

**Sí cubre:**
- Empaquetar las 5 imágenes en el repo, en su resolución original (decisión ya tomada: prioridad
  a la calidad en monitores 4K/8K reales sobre el peso del repo).
- Una miniatura PNG pre-generada por imagen (fuzzel documenta soporte de iconos para PNG/SVG, no
  JPEG — generar miniaturas evita apostar a que el JPEG cargue, y de paso evita decodificar un
  JPEG de varios MB cada vez que se abre el selector).
- Una pregunta nueva en el asistente de instalación (`lib/phase2.sh`), **por nombre** — igual que
  la pregunta de tema hoy, sin vista previa visual ahí (limitación real: el asistente es una TUI
  de terminal, no puede mostrar imágenes).
- Mejorar el selector gráfico ya existente (`archfrican-wallpaper`, alcanzable por
  `Mod+Shift+A → Wallpaper`) para mostrar las 5 miniaturas reales como accesos rápidos en fuzzel,
  preservando la opción actual de tipear una ruta custom.

**Explícitamente fuera de alcance** (decisiones tomadas durante el brainstorming):
- **Ningún mapeo automático imagen-por-tema.** Las 5 quedan disponibles para cualquier tema; no
  se fuerza "esta imagen solo con este tema".
- **Sin compresión/redimensionado de los JPEG originales** — se guardan tal cual.
- **Sin miniaturas en el asistente de instalación** — técnicamente no viable en una TUI de
  terminal; el asistente pregunta por nombre, igual que ya hace con el tema.
- **Sin generación de miniaturas en tiempo de ejecución** — se generan una sola vez ahora y se
  commitean, para no sumarle una dependencia nueva (ImageMagick) a un script que hoy no la
  necesita (`archfrican-wallpaper` solo depende de `matugen`/`jq`).

## Arquitectura

### Almacenamiento

`assets/wallpapers/` (nueva carpeta, mismo criterio que `assets/sddm/` y `assets/plymouth/`
existentes):

```
assets/wallpapers/
├── Archfrican-Blue.jpg      (original, sin tocar)
├── Archfrican-Cross.jpg
├── Archfrican-Cube.jpg
├── Archfrican-CubeTwo.jpg
├── Archfrican-Curve.jpg
└── thumbs/
    ├── Archfrican-Blue.png    (320×180, generada una vez con ImageMagick, ~80-100KB)
    ├── Archfrican-Cross.png
    ├── Archfrican-Cube.png
    ├── Archfrican-CubeTwo.png
    └── Archfrican-Curve.png
```

### Asistente de instalación (`lib/phase2.sh`)

Una pregunta nueva en el bloque interactivo, junto a la de tema (mismo patrón que
`ui_choose 'Initial theme' ...`):

```bash
WALLPAPER="$(ui_choose 'Wallpaper' 'Ninguno (color sólido)' 'Blue' 'Cross' 'Cube' 'CubeTwo' 'Curve')"
```

Si se elige un nombre (no "Ninguno"), se escribe su ruta absoluta
(`$REPO_ROOT/assets/wallpapers/Archfrican-<Nombre>.jpg`) en `~/.config/archfrican/wallpaper` —
**el mismo archivo que ya lee `archfrican-wallpaper-restore` hoy** (cero mecanismo nuevo). Si se
elige "Ninguno", no se escribe nada, y el flujo existente sigue cayendo al color sólido tal cual
funciona ahora. La aplicación real (llamar a `awww img` + generar el retinte Material You vía
`archfrican-wallpaper`) ocurre en el primer login, igual que ya pasa con el tema elegido en el
asistente.

### Selector gráfico (`archfrican-wallpaper`)

El script hoy NO tiene ninguna variable que resuelva la raíz del repo (no la necesita: solo
trabaja con rutas de imagen que el usuario da). Para poder encontrar `assets/wallpapers/` tanto
si corre desde el repo de desarrollo como desde el clon desplegado en `~/.archfrican`, se le suma
el mismo patrón que ya usa `bin/theme-switch`: `ROOT="${ARCHFRICAN_ROOT:-$HOME/.archfrican}"`.

Hoy:
```bash
img="${1:-}"
[ -n "$img" ] || img="$(fuzzel --dmenu --prompt 'ruta de la imagen:  ' </dev/null)" || exit 0
```

Pasa a mostrar primero las 5 miniaturas (protocolo de iconos de fuzzel, `\0icon\x1f<ruta-png>`,
verificado que funciona con imágenes propias — no solo nombres de tema de iconos, ya lo usa
`archfrican-spotlight` para los iconos de apps), y al final una entrada "Elegir un archivo…" que
preserva el comportamiento actual (tipear/pegar una ruta):

```bash
img="${1:-}"
if [ -z "$img" ]; then
  sel="$(
    { for f in "$ROOT/assets/wallpapers"/*.jpg; do
        name="$(basename "$f" .jpg)"
        thumb="$ROOT/assets/wallpapers/thumbs/$name.png"
        printf '%s\0icon\x1f%s\n' "$name" "$thumb"
      done
      printf 'Elegir un archivo…\n'
    } | fuzzel --dmenu --prompt '  wallpaper  '
  )" || exit 0
  case "$sel" in
    "Elegir un archivo…"|"") img="$(fuzzel --dmenu --prompt 'ruta de la imagen:  ' </dev/null)" || exit 0 ;;
    *) img="$ROOT/assets/wallpapers/$sel.jpg" ;;
  esac
fi
```

El resto del script (persistir la ruta, `awww img`, retinte con `matugen --prefer saturation`)
no cambia.

## Manejo de errores

- Si `assets/wallpapers/` no existe en una instalación vieja que no actualizó el repo, el glob
  `*.jpg` no encuentra nada — el menú muestra solo "Elegir un archivo…", sin romperse.
- Si una miniatura específica falta, fuzzel simplemente no muestra ícono para esa entrada (no
  falla) — mismo comportamiento tolerante que ya usa `archfrican-spotlight` cuando un `.desktop`
  no tiene `Icon=`.

## Testing / validación

- Ya validado durante el brainstorming: `convert -resize 320x180` genera una miniatura de ~86KB
  con buena nitidez visual (probado con Archfrican-Blue.jpg).
- Verificar en vivo: el selector gráfico muestra las 5 miniaturas reales (no solo texto), elegir
  una aplica el wallpaper + retinte correctamente, "Elegir un archivo…" sigue aceptando una ruta
  custom como hoy.
- `bash -n` sobre `archfrican-wallpaper` y `lib/phase2.sh` tras los cambios.
- Confirmar que una instalación con "Ninguno" elegido en el asistente sigue cayendo al color
  sólido exactamente como antes (no debe escribir nada en `~/.config/archfrican/wallpaper`).
