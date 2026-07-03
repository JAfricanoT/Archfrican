# Deep clean — Fase 0: cimientos en modo dry-run

## Contexto

Este documento opera un único tramo (Fase 0) del plan completo, ya aprobado, en
`docs/superpowers/plans/quiero-que-mejoremos-como-frolicking-peach.md` (copia local del
plan de la sesión de diseño — "limpieza profunda / factory reset preservando /home").
Fase 0 es **puro andamiaje**: nada de lo que se construye aquí es alcanzable desde ningún
menú, script disparador, ni `install.sh`. El objetivo es que exista el esqueleto completo
de la lógica de wipe/pacstrap/config-de-chroot detrás de un gate dry-run-por-defecto, listo
para que Fase 1 (mecanismo de arranque real) lo conecte a algo ejecutable de verdad.

Cita textual del plan aprobado para esta fase:

> **Fase 0 — Cimientos en modo dry-run.** `lib/deep-clean.sh` con toda la lógica de
> wipe/pacstrap/chroot-config detrás de `AF_GO`-equivalente (imprime el plan, ejecuta nada
> salvo `ARCHFRICAN_DEEPCLEAN_ARMED=1`). Job de CI `deepclean-safety-gate`. Entrada nueva en
> `GOVERNANCE.md`. Nada de esto es alcanzable desde ningún lado todavía — es puro andamiaje
> verificable por lectura de código y CI.

## Global Constraints (aplican a las 3 tasks)

- **Namespacing obligatorio, nunca reutilizar `run`/`run_pipe`/`probe`/`AF_GO` de
  `lib/base-install.sh`.** Todas las libs de `lib/*.sh` se sourcean juntas en el mismo shell
  (ver `install.sh` líneas 53-68) — si `lib/deep-clean.sh` reutilizara los nombres genéricos
  `run()`/`AF_GO`, un `AF_GO=1` puesto por el instalador ISO ejecutaría también la lógica de
  deep-clean por accidente, mezclando dos gates independientes. Usar exclusivamente:
  variable de gate `DC_GO` (no `AF_GO`), funciones `dc_run()`, `dc_run_pipe()`, `dc_probe()`
  (no `run`/`run_pipe`/`probe`), variable de arming `ARCHFRICAN_DEEPCLEAN_ARMED` (no
  `ARCHFRICAN_ISO_ARMED`).
- **`ARCHFRICAN_DEEPCLEAN_ARMED` debe defaultear a `0`**, con esta línea EXACTA (verbatim,
  la task 2 la verifica por grep):
  ```bash
  ARCHFRICAN_DEEPCLEAN_ARMED="${ARCHFRICAN_DEEPCLEAN_ARMED:-0}"
  ```
- **La lista de subvolúmenes a borrar es SIEMPRE literal, jamás calculada** desde `btrfs
  subvolume list` ni ninguna otra enumeración en vivo. Línea EXACTA (verbatim, la task 2 la
  verifica por grep):
  ```bash
  DEEPCLEAN_DELETE_SUBVOLS=(@ @log @pkg @.snapshots)
  ```
  `@home` NUNCA puede estar en esa lista. Esto se refuerza en dos capas independientes: (a)
  la lista es un literal fijo en el código — no hay ninguna función que la construya; (b)
  una guarda en tiempo de ejecución (`dc_guard_allowlist`, ver Task 1) que hace `die` si
  alguna vez `@home` apareciera ahí. Las dos capas son intencionales — no es redundancia a
  eliminar.
- **`lib/deep-clean.sh` no puede contener, en ningún punto del archivo, ninguna de estas
  cuatro cadenas literales**: `mkfs.btrfs`, `cryptsetup luksFormat`, `wipefs`, `sgdisk`. Esas
  cuatro son operaciones de reformateo de disco completo — deep-clean SOLO opera a nivel de
  subvolumen btrfs sobre un filesystem que ya existe. La task 2 verifica esto por grep en CI.
- Todo lo que hoy sería destructivo (borrar un subvolumen, montar, pacstrap, mkinitcpio,
  grub-install, mover/renombrar subvolúmenes) pasa por `dc_run`/`dc_run_pipe` — nunca se
  invoca el comando real directamente.
- Nada de esto se sourcea desde `install.sh` todavía, ni se referencia desde ningún menú
  (`archfrican-actions`, `actions.toml.tmpl`, etc.) — eso es explícitamente trabajo de una
  fase posterior (Fase 5, gate de atestación).
- Commits: modular por task, Conventional Commit, **sin ninguna atribución de IA/Claude/Co-
  Authored-By** en el mensaje (norma del repo).

## Task 1: `lib/deep-clean.sh` — esqueleto dry-run + test de fixture del allowlist

**Archivos**: crear `lib/deep-clean.sh`; crear `tests/unit/deep-clean.sh`.

### Qué construir

Usar `lib/base-install.sh` (ya en el repo) como referencia directa de estilo y estructura —
mismo patrón de wrappers dry-run, mismo estilo de comentario de cabecera "SAFETY box", mismas
convenciones de nombres de función (pero con el prefijo `dc_` y el gate `DC_GO`, ver Global
Constraints). NO es obligatorio copiar la implementación de abajo tal cual — es un punto de
partida razonable, no la única forma correcta; usa tu criterio si algo se puede expresar
mejor, siempre y cuando cumplas las Global Constraints al pie de la letra.

Estructura esperada (nombres de función y variables exactos — los reusan `install.sh` y
tests de fases futuras):

```bash
#!/usr/bin/env bash
# Deep clean (factory reset preservando /home) — Fase 0: andamiaje en modo dry-run.
# [cabecera SAFETY box explicando DC_GO / ARCHFRICAN_DEEPCLEAN_ARMED / el namespacing
#  deliberado frente a run()/AF_GO de lib/base-install.sh]

ARCHFRICAN_DEEPCLEAN_ARMED="${ARCHFRICAN_DEEPCLEAN_ARMED:-0}"
DC_GO=0

dc_run() { ... }        # como run() de base-install.sh pero gateado en DC_GO
dc_run_pipe() { ... }   # como run_pipe()
dc_probe() { ... }      # como probe()

DEEPCLEAN_DELETE_SUBVOLS=(@ @log @pkg @.snapshots)

dc_guard_allowlist() {
  # itera DEEPCLEAN_DELETE_SUBVOLS, die si "@home" aparece
}

dc_stale_guard() { ... }          # análogo a base_stale_guard: libera montajes de un intento previo abortado
dc_detect_managed_layout() { ... } # Fase 0: placeholder de solo-lectura (dc_probe), Fase 1 lo implementa de verdad
dc_wipe_subvolumes() { ... }       # llama dc_guard_allowlist, luego dc_run btrfs subvolume delete por cada entrada
dc_pacstrap_new() { ... }          # crea @.new, monta, pacstrap ahí (nunca toca @ directamente)
dc_chroot_config_new() { ... }     # arch-chroot al sistema nuevo dentro de @.new
dc_atomic_swap() { ... }           # @ -> @.old, @.new -> @, borrar @.old (última operación, ventana mínima)

run_deep_clean() {
  dc_guard_allowlist
  if [ "$ARCHFRICAN_DEEPCLEAN_ARMED" = 1 ]; then DC_GO=1; fi
  dc_stale_guard
  dc_detect_managed_layout
  dc_wipe_subvolumes
  dc_pacstrap_new
  dc_chroot_config_new
  dc_atomic_swap
}
```

Requisitos de comportamiento (no solo de forma):
- Con `ARCHFRICAN_DEEPCLEAN_ARMED` sin definir (o `=0`), `run_deep_clean` (y cada función
  interna) NO debe ejecutar ningún comando real — solo imprimir a stderr con el mismo estilo
  `[dry-run]` que usa `lib/base-install.sh`.
- `dc_guard_allowlist` se llama tanto al inicio de `run_deep_clean` como dentro de
  `dc_wipe_subvolumes` (defensa en profundidad — no confiar en que se llamó una sola vez
  arriba del todo).
- Usa `die`/`warn`/`substep` de `lib/common.sh` (no los reimplementes) — el archivo asume que
  ya fue sourceado `lib/common.sh` antes (mismo patrón que `lib/base-install.sh`).

### Test de fixture: `tests/unit/deep-clean.sh`

Modelo a seguir: `tests/unit/disk.sh` (mockea comandos externos, contador P/F, `set -uo
pipefail` + `set +e` para capturar códigos de salida tú mismo, exit final `[ "$F" -eq 0 ]`).
Sourcea `lib/common.sh` y luego `lib/deep-clean.sh`.

Debe probar, como mínimo:
1. **El allowlist es SIEMPRE la lista fija, nunca calculada** — mockea `btrfs` (la función
   `btrfs() { ... }` shadowea el binario real) para que `btrfs subvolume list` devuelva
   subvolúmenes inesperados (incluyendo uno falso `@home2`, uno reordenado, uno que no
   debería existir) y confirma que `DEEPCLEAN_DELETE_SUBVOLS` sigue siendo exactamente
   `(@ @log @pkg @.snapshots)` sin importar qué devuelva el mock — es decir, prueba que
   ninguna función deriva la lista de ese mock.
2. **`dc_guard_allowlist` muere si `@home` aparece en la lista** — en un subshell (`out="$(
   DEEPCLEAN_DELETE_SUBVOLS=(@ @home); dc_guard_allowlist )"; rc=$?`, igual que el patrón
   `out="$( set -euo pipefail; live_disk )"; rc=$?` de `tests/unit/disk.sh` — así el `exit 1`
   de `die` dentro de `dc_guard_allowlist` no mata el script de test completo), confirma
   `rc != 0`.
3. **Dry-run por defecto no ejecuta nada** — con `ARCHFRICAN_DEEPCLEAN_ARMED` sin definir,
   mockea el comando subyacente que `dc_run`/`dc_run_pipe` invocarían (p. ej. `btrfs`,
   `mount`, `pacstrap`) para que incremente un contador si se llama de verdad; corre
   `dc_wipe_subvolumes` (o `run_deep_clean` completo con los demás pasos también mockeados) y
   confirma que el contador queda en 0.
4. **`ARCHFRICAN_DEEPCLEAN_ARMED=1` activa `DC_GO`** dentro de `run_deep_clean` — no hace
   falta llegar a ejecutar todo el flujo real (eso es Fase 1); alcanza con confirmar que
   `DC_GO` pasa a `1` cuando `ARCHFRICAN_DEEPCLEAN_ARMED=1` está en el entorno al llamar
   `run_deep_clean` (puedes mockear todos los comandos externos que toque para que la llamada
   no falle).

### Reporte

DONE cuando: `bash -n lib/deep-clean.sh` pasa, `shellcheck -x -e SC1091 lib/deep-clean.sh`
pasa, `bash tests/unit/deep-clean.sh` pasa (imprime "N passed, 0 failed"), commit hecho.
Reporta el comando de test exacto corrido y su output en el reporte.

---

## Task 2: CI — job `deepclean-safety-gate` + wiring del test de fixture

**Depende de Task 1** (los greps de este job apuntan a `lib/deep-clean.sh`, que Task 1 crea).

**Archivo**: `.github/workflows/ci.yml`.

### Job nuevo `deepclean-safety-gate`

Insertar inmediatamente después del job `iso-safety-gate` existente (líneas ~54-63 al momento
de escribir este brief — verifica la posición exacta con `grep -n iso-safety-gate
.github/workflows/ci.yml` antes de editar), mismo estilo y estructura que ese job:

```yaml
  deepclean-safety-gate:
    runs-on: ubuntu-latest        # el wipe de deep-clean debe shippear DESHABILITADO y nunca reformatear
    steps:
      - uses: actions/checkout@v4
      - name: deep-clean defaults to dry-run + never reformats (subvolume-only)
        run: |
          set -euo pipefail
          grep -qE '^ARCHFRICAN_DEEPCLEAN_ARMED="\$\{ARCHFRICAN_DEEPCLEAN_ARMED:-0\}"$' lib/deep-clean.sh \
            || { echo "::error::lib/deep-clean.sh must DEFAULT ARCHFRICAN_DEEPCLEAN_ARMED to 0 (env-overridable; never hardcode =1)"; exit 1; }
          grep -qF 'DEEPCLEAN_DELETE_SUBVOLS=(@ @log @pkg @.snapshots)' lib/deep-clean.sh \
            || { echo "::error::lib/deep-clean.sh must define the FIXED subvolume delete allowlist verbatim (never computed)"; exit 1; }
          if grep -qE 'mkfs\.btrfs|cryptsetup luksFormat|wipefs|sgdisk' lib/deep-clean.sh; then
            echo "::error::lib/deep-clean.sh must NEVER reformat — found a full-disk-wipe verb (mkfs.btrfs/luksFormat/wipefs/sgdisk)"; exit 1
          fi
          echo "deepclean-safety: dry-run default OK, fixed allowlist OK, no full-disk-wipe verbs"
```

(El bloque `run:` de arriba es el contenido exacto a usar — cópialo tal cual, solo ajustando
indentación YAML si hace falta.)

### Wiring del test de fixture en el job `unit-logic`

Agregar un step nuevo al job `unit-logic` ya existente (mismo lugar donde están
`tests/unit/disk.sh`, `tests/unit/manifest.sh`, etc.), siguiendo el mismo formato `- name: ...
\n  run: bash tests/unit/X.sh` que ya usan los demás steps de ese job:

```yaml
      - name: deep-clean allowlist — fixed, never computed; @home guard; dry-run-by-default
        run: bash tests/unit/deep-clean.sh
```

### Reporte

DONE cuando: el YAML resultante pasa `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"`
(o cualquier validador YAML disponible) sin error, el nuevo job aparece con `grep -n
deepclean-safety-gate .github/workflows/ci.yml`, y el nuevo step aparece bajo `unit-logic` con
`grep -n "tests/unit/deep-clean.sh" .github/workflows/ci.yml` (dos ocurrencias esperadas: el
job dedicado NO ejecuta ese test — solo hace grep sobre `lib/deep-clean.sh`; el step nuevo en
`unit-logic` sí lo ejecuta). Ajusta esa expectativa de conteo si tu implementación difiere,
pero explica por qué en el reporte. Commit hecho.

---

## Task 3: `GOVERNANCE.md` — nuevos invariantes protegidos (inglés + español)

**No depende de Task 1/2** en términos de contenido de archivo, pero conceptualmente describe
lo que esas tasks construyen — dispáchala después para que el redactor pueda citar nombres de
archivo/job reales si le sirve de contexto (no es obligatorio, el texto se puede escribir sin
mirar el código).

**Archivo**: `GOVERNANCE.md`.

### Qué agregar

En la sección `### Special rule — security / disk / boot / auth changes` (inglés) y su espejo
`### Regla especial — cambios de seguridad / disco / arranque / auth` (español), el punto 3
("Safety gates held" / "Gates de seguridad intactos") ya enumera los invariantes protegidos
existentes (`ARCHFRICAN_ISO_ARMED` en 0, `confirm_wipe`, FIDO2, firewall, CachyOS pin) y
menciona qué jobs de CI los hacen cumplir. Extender ESA MISMA lista (no crear una sección
nueva) con los invariantes de deep-clean, y extender la mención de jobs de CI para incluir
`deepclean-safety-gate` junto a `iso-safety-gate` + `firewall-ruleset`.

Invariantes a agregar a la lista (versión en inglés, adaptar el mismo contenido al español
en el bloque espejo — no es traducción palabra por palabra obligatoria, pero debe cubrir los
mismos tres puntos):
- `ARCHFRICAN_DEEPCLEAN_ARMED` defaults to `0` (the deep-clean wipe defaults to dry-run
  preview, same pattern as `ARCHFRICAN_ISO_ARMED`).
- The subvolume delete allowlist (`DEEPCLEAN_DELETE_SUBVOLS`) is a **fixed literal, never
  computed** from a live `btrfs subvolume list` — `@home` may never appear in it, enforced
  both by the literal itself and by a runtime `die` guard.
- Deep-clean only ever operates at the btrfs-subvolume level — it may never call a full-disk
  reformat verb (`mkfs.btrfs`, `cryptsetup luksFormat`, `wipefs`, `sgdisk`).

Actualizar también la frase final del punto 3 para que mencione que `deepclean-safety-gate`
(además de `iso-safety-gate` + `firewall-ruleset`) hace cumplir mecánicamente parte de esto —
sigue el mismo estilo de la frase existente ("The CI `iso-safety-gate` + `firewall-ruleset`
jobs enforce two of these mechanically.").

No toques ninguna otra sección de `GOVERNANCE.md` (Model, Merge requirements, Releases,
Becoming a maintainer) — son ortogonales a este trabajo.

### Reporte

DONE cuando: ambos bloques (inglés y español) mencionan los 3 invariantes nuevos y el job
`deepclean-safety-gate`, el archivo sigue siendo Markdown válido, y ningún otro contenido del
archivo cambió (verificable con `git diff GOVERNANCE.md` — el diff debe tocar solo el punto 3
de ambas secciones "Special rule"/"Regla especial"). Commit hecho.
