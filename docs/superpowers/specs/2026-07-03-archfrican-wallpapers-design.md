# Bundle curated Archfrican wallpapers, selectable at install and afterward

## Contexto

Hoy Archfrican no incluye ninguna imagen de fondo propia: si el usuario nunca elige una con
`archfrican-wallpaper`, `archfrican-wallpaper-restore` cae a un color sólido tomado del tema
activo (`#1c1c1e` en `archfrican-dark`, por ejemplo) — nunca queda en negro puro, pero tampoco
hay una identidad visual de marca en el fondo.

El usuario proveyó 5 imágenes propias (`Archfrican-{Blue,Cross,Cube,CubeTwo,Curve}.jpg`,
3840×2160 a 8000×4500, JPEG). Las cinco comparten una misma familia visual: abstractas, fondo
oscuro/negro, vidrio y prismas 3D con el mismo azul de acento del sistema (`#0a84ff`) que ya usa
todo el tema — encajan directamente con la identidad "macOS-grade" que el proyecto ya declara en
`docs/DESIGN-LANGUAGE.md`. Ninguna es de paleta clara, así que son candidatas naturales para los
temas oscuros (no se fuerza ningún mapeo tema-por-tema todavía).

**Nota de reconciliación:** el diseño original de este spec asumía que `archfrican-wallpaper`
todavía era un simple "tipeá una ruta". Mientras se escribía este documento, otra sesión
concurrente reescribió ese script: ahora escanea `~/Pictures`, `~/Downloads`,
`/usr/share/backgrounds` y `~/.local/share/backgrounds` (hasta 3 niveles) buscando imágenes, y
muestra la lista con **Walker** como picker principal (cae a fuzzel si Walker/elephant no
responden). Esto simplifica bastante el diseño: **no hace falta tocar ese script en absoluto**
— alcanza con que las 5 imágenes vivan en una carpeta que el escaneo ya cubre.

## Alcance

**Sí cubre:**
- Empaquetar las 5 imágenes en el repo (`assets/wallpapers/`), en su resolución original
  (decisión ya tomada: prioridad a la calidad en monitores 4K/8K reales sobre el peso del repo).
- Desplegarlas a `/usr/share/backgrounds/archfrican/` durante la instalación/convergencia — el
  mismo lugar que `archfrican-wallpaper` ya escanea hoy, así que quedan seleccionables desde el
  picker existente sin ningún cambio de código ahí.
- Una pregunta nueva en el asistente de instalación (`lib/phase2.sh`), **por nombre** — igual que
  la pregunta de tema hoy, sin vista previa visual ahí (limitación real: el asistente es una TUI
  de terminal, no puede mostrar imágenes). Si el usuario elige una, queda aplicada desde el
  primer login, sin tener que buscarla manualmente después.

**Explícitamente fuera de alcance** (decisiones tomadas durante el brainstorming):
- **Ningún mapeo automático imagen-por-tema.** Las 5 quedan disponibles para cualquier tema; no
  se fuerza "esta imagen solo con este tema".
- **Sin compresión/redimensionado de los JPEG originales** — se guardan tal cual.
- **Sin miniaturas ni cambios al picker gráfico.** Se evaluó agregar un menú fuzzel dedicado con
  miniaturas reales (protocolo de iconos), pero se descartó a favor de reusar el escaneo de
  carpetas ya existente — más simple, sin tocar `archfrican-wallpaper`, sin depender de si Walker
  soporta o no ese protocolo de iconos (no se pudo confirmar visualmente).
- **Sin miniaturas en el asistente de instalación** — técnicamente no viable en una TUI de
  terminal; el asistente pregunta por nombre, igual que ya hace con el tema.

## Arquitectura

### Almacenamiento y despliegue

`assets/wallpapers/` (nueva carpeta, mismo criterio que `assets/sddm/` y `assets/plymouth/`
existentes) — sin subcarpetas ni miniaturas, solo los 5 JPG originales:

```
assets/wallpapers/
├── Archfrican-Blue.jpg
├── Archfrican-Cross.jpg
├── Archfrican-Cube.jpg
├── Archfrican-CubeTwo.jpg
└── Archfrican-Curve.jpg
```

Se despliegan a `/usr/share/backgrounds/archfrican/` con el mismo patrón ya usado para el tema de
SDDM en `modules/20-niri-desktop.sh:15-16`:

```bash
sudo install -d -m 0755 /usr/share/backgrounds/archfrican
sudo cp -a "$REPO_ROOT/assets/wallpapers/." /usr/share/backgrounds/archfrican/
```

Se agrega justo al lado de la copia de assets de SDDM en ese mismo módulo (mismo módulo, misma
sección — ambos son "copiar assets estáticos a una ruta de sistema"). También se suma
`assets/wallpapers` a la lista de inputs de `20-niri-desktop` en `lib/converge.sh`
(`module_inputs()`), para que agregar/cambiar una imagen dispare la reconvergencia igual que ya
pasa con `assets/sddm/archfrican`.

`archfrican-wallpaper` NO se toca: su `find ... /usr/share/backgrounds ...` (`-maxdepth 3`) ya
alcanza `/usr/share/backgrounds/archfrican/*.jpg` sin ningún cambio.

### Asistente de instalación (`lib/phase2.sh`)

Una pregunta nueva en el bloque interactivo, junto a la de tema (mismo patrón que
`ui_choose 'Initial theme' ...`):

```bash
WALLPAPER="$(ui_choose 'Wallpaper' 'Ninguno (color sólido)' 'Blue' 'Cross' 'Cube' 'CubeTwo' 'Curve')"
```

Si se elige un nombre (no "Ninguno"), se escribe su ruta absoluta
(`/usr/share/backgrounds/archfrican/Archfrican-<Nombre>.jpg` — la ruta DESPLEGADA de sistema, no
la del repo) en `~/.config/archfrican/wallpaper`, junto con el resto del staging que ya hace esa
sección (tema, teclado). **El mismo archivo que ya lee `archfrican-wallpaper-restore` hoy** — cero
mecanismo nuevo. Si se elige "Ninguno", no se escribe nada, y el flujo existente sigue cayendo al
color sólido tal cual funciona ahora. La aplicación real (`awww img` + retinte Material You)
ocurre en el primer login, igual que ya pasa con el tema elegido en el asistente.

## Manejo de errores

- Si `assets/wallpapers/` no existe en una instalación vieja que no re-convergió, simplemente no
  hay nada bajo `/usr/share/backgrounds/archfrican/` — el picker existente sigue funcionando
  igual con lo que encuentre en las otras carpetas (comportamiento actual, sin cambios).
- La copia (`sudo cp -a`) es la misma operación idempotente que ya usa SDDM — correr la
  convergencia de nuevo simplemente sobreescribe con el mismo contenido.

## Testing / validación

- `bash -n` sobre `modules/20-niri-desktop.sh` y `lib/phase2.sh` tras los cambios.
- Verificar en vivo: tras converger, `/usr/share/backgrounds/archfrican/*.jpg` existen; abrir el
  picker de `archfrican-wallpaper` (`Mod+Shift+A → Wallpaper`) y confirmar que las 5 aparecen en
  la lista (por nombre de archivo, vía Walker o fuzzel según corresponda).
- Confirmar que una instalación con "Ninguno" elegido en el asistente sigue cayendo al color
  sólido exactamente como antes (no debe escribir nada en `~/.config/archfrican/wallpaper`).
- Confirmar que `archfrican-doctor`/`drift_modules` detecta drift si se edita/agrega una imagen
  en `assets/wallpapers/` sin re-converger (prueba de que `module_inputs()` quedó bien cableado).
