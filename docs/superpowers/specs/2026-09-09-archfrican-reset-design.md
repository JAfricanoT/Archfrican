# `archfrican-reset` — asistente de reparación y restablecimiento (diseño)

## Contexto

El usuario pidió que el procedimiento de factory reset —conservando o no sus archivos— se
simplificara hasta que "no tenga que estar metiendo comandos". Hoy no existe ningún reset
guiado: `docs/RECOVERY.md` §10 documentaba un procedimiento que preservaba `/home` y era
falso (corregido en `2ac3a20` — el instalador ISO hace `wipefs --all` + `sgdisk --zap-all` +
`mkfs.btrfs -f`, `lib/base-install.sh:55-80`).

Este documento diseña `archfrican-reset`: un asistente de cuatro niveles accesible desde el
menú de acciones. Cuatro agentes diseñaron sus partes en paralelo; un panel de cinco expertos
(pérdida de datos, factor humano, arquitectura, fiabilidad operativa, testabilidad) arbitró los
ocho conflictos entre ellos y encontró dos rutas críticas a pérdida total que el diseño
original no veía. Las resoluciones del panel están incorporadas aquí, no anexadas.

**No confundir con el "deep clean"** (`lib/deep-clean.sh`, factory reset en sitio preservando
`@home`): ese es otro proyecto, con su Fase 0 construida y su Fase 1 especificada en
`docs/superpowers/specs/2026-07-03-deepclean-fase1-boot-mechanism-design.md`, sin trigger. El
Nivel 4 de este asistente es exactamente el hueco reservado para él.

---

## 1. Los cuatro niveles

| Entrada del menú | Cols | Qué hace | Qué pierdes |
|---|---|---|---|
| `Reparar el sistema  ·  no borra archivos` | 40 | Re-aplica módulos y dotfiles | Ediciones locales a dotfiles gestionados (se copian antes) |
| `Restablecer  ·  tus archivos se quedan` | 38 | + quita paquetes fuera del manifiesto y huérfanos | Lo anterior + paquetes instalados a mano |
| `Preparar borrado total  ·  necesita USB` | 39 | Respalda, verifica y graba el USB de instalación | El USB se formatea **hoy**; el disco, al arrancar desde él |
| `Limpieza profunda  ·  aún no disponible` | 39 | Explica qué hará y qué usar mientras tanto | — |

**Restricción dura de anchura.** `templates/fuzzel.ini:9-10` fija `width=46` y `lines=12`, y
`card()` (`executable_archfrican-welcome:11`) mete cada línea como una fila de `--dmenu`, que
fuzzel **no envuelve: trunca**. Ningún `text` puede pasar de **41 caracteres** y ninguna
tarjeta de **12 líneas**. El nombre originalmente aprobado, `Restablecer a fábrica · conserva
tus archivos`, son 47 caracteres: se cortaba dejando en pantalla "fábrica" y borrando la
salvedad — el peor resultado posible, y la razón por la que se descartó.

**`subtext` es invisible en el fallback.** `toml_menu_list` (`archfrican-common.sh:78-79`)
imprime solo `text`. La consecuencia va siempre en `text`; el `subtext` solo amplía.

---

## 2. Arquitectura

### `lib/reset.sh` — modelada sobre `lib/rollback.sh`, NO sobre `lib/deep-clean.sh`

`lib/rollback.sh` no usa ni un helper de `lib/common.sh`, y por eso
`executable_archfrican-rollback:18` puede sourcearla sola. `lib/deep-clean.sh:7` declara lo
contrario ("Sourced after lib/common.sh"), y `lib/common.sh:4` es `set -euo pipefail` a nivel
de archivo: bajo un menú, **cada fuzzel cancelado (rc 1) mataría el asistente en silencio**. El
repo ya tropezó con esto dos veces y lo dejó escrito (`tests/unit/deep-clean.sh:21`,
`bin/archfrican-update:26`).

**Reglas duras:**
- `lib/reset.sh` es autocontenida. Devuelve códigos de retorno; **nunca `die`**.
- No sourcea `lib/common.sh` ni `lib/deep-clean.sh`, y no toca `DC_GO` /
  `ARCHFRICAN_DEEPCLEAN_ARMED` — dos gates que comparten shell colapsan en uno
  (`lib/deep-clean.sh:15-23`).
- `prune_candidates` (`lib/manifest.sh:52-68`) se reutiliza tal cual, nunca se reimplementa.
  No necesita `REPO_ROOT` ni `read_pkg_list` pese a la cabecera de `lib/manifest.sh:11` — esos
  son de `write_manifest`, que `lib/reset.sh` **nunca** debe llamar (lo hace el converge,
  `lib/phase2.sh:277`).
- **No hay wrappers dry-run genéricos.** Los Niveles 1-2 no escriben en bloques. La única
  operación que los necesita es `rs_write_iso`, y ahí basta una guarda dentro de esa función
  (`ARCHFRICAN_RESET_ARMED`, default `0`). Tres wrappers genéricos para un solo call site es
  donde nace la deriva.

### `~/.local/bin/archfrican-reset` — capa de menú

Guard obligatorio, copiado literal de `executable_archfrican-rollback:14-18`: default
`$HOME/.archfrican`, `[ -r ... ]` + `note` + exit si falta. `ARCHFRICAN_ROOT` es una feature
declarada (`bin/theme-switch:8`, `docs/VALIDATION.md:83`): se respeta, no se defiende contra ella.

Como el reset **ejecuta `$REPO_ROOT/install.sh`**, un clon viejo aplica un estado deseado
obsoleto. `--update` no hace `git pull` (correcto: eso es trabajo de `archfrican-update`), así
que la pantalla del Nivel 1 **muestra el commit que va a aplicar**
(`git -C "$ROOT" log -1 --format='%h %s'`).

### `home/dot_config/elephant/menus/restablecer.toml.tmpl`

La puerta en `actions.toml.tmpl` va junto a `Revertir actualización (rollback)…` (`:196`), no
arriba: el hub es `fixed_order = true` y agrupa la recuperación al final.

**La puerta es `actions = { run = ... }`, nunca `submenu =`.** Con `submenu`, Walker renderiza
el TOML nativamente y el script nunca corre — se perdería la detección de un restablecimiento
interrumpido y el estado real del respaldo. Es lo que ya hace `archfrican-setup:14`.

**Los Niveles 1 y 2 llevan `terminal = true`.** El Nivel 2 pide contraseña de sudo y el Y/N de
`pacman -Rns`: sin TTY se cuelga o muere mudo. El diseño original solo se lo puso al Nivel 1.

---

## 3. Nivel 1 — Reparar

```
rs_lock                                   # mismo lockdir que archfrican-update
rs_dotfile_edits  → preview + copia write-once a ~/.local/state/archfrican/reset-<ts>/dotfiles/
rs_snapshot root  --cleanup-algorithm number --userdata important=yes
FORCE=1 bash "$REPO_ROOT/install.sh" --update
archfrican-doctor
```

`FORCE=1`, no selectivo por drift: `drift_modules` (`lib/converge.sh:68-75`) compara *inputs
del repo* contra el hash estampado, así que un sistema roto con el repo intacto no muestra
drift y `--update` lo saltaría todo (`lib/phase2.sh:58`). Reparar existe justo para el caso "el
estampado miente".

`--update` y no `install.sh` a secas: pone `ARCHFRICAN_UPDATE=1 ARCHFRICAN_NONINTERACTIVE=1`
(`install.sh:79-81`), sin wizard y sin re-aplicar identidad (`lib/phase2.sh:199-215`).

**Puerta condicional** (C3): si `rs_dotfile_edits` devuelve 0 archivos, ejecuta sin preguntar.
Si devuelve N>0, una sola pantalla que los nombra. El permiso se pide solo cuando hay algo que
perder, que es la única forma de que no se devalúe.

---

## 4. Nivel 2 — Restablecer

```
1. rs_lock  +  systemd-inhibit --what=sleep:shutdown:idle
2. preview (solo lectura) — cancelar aquí no deja rastro
3. copia write-once de los dotfiles editados   ← ANTES del converge, que los destruye
4. rs_snapshot root  +  rs_snapshot home
5. FORCE=1 install.sh --update                 ← repara, aplica dotfiles, REESCRIBE el manifiesto
6. clausura real de la poda → confirmar → pacman -Rs
7. huérfanos recalculados → confirmar → pacman -Rs
8. archfrican-doctor + aviso de reinicio
```

**Converger antes de podar.** `prune_candidates` es relativo al manifiesto
(`lib/manifest.sh:59`), y el manifiesto solo se reescribe al final del converge
(`lib/phase2.sh:277`) con los opt-ins re-detectados en vivo (`:180-186`). Podar antes borra
contra un estado obsoleto. Mismo orden que `archfrican-update --run` (`:375` vs `:405`).
**Este orden vive en el código con su comentario-porqué**, o un futuro refactor de
`write_manifest` lo rompe en silencio.

**Huérfanos después de la poda**, porque `-Rs` arrastra dependencias y crea huérfanos nuevos.

**No hay `chezmoi apply --force` propio**: ya lo hace el converge (`lib/phase2.sh:244`).

---

## 5. Nivel 3 — Preparar borrado total

**El asistente sí destruye hoy: formatea el USB.** El diseño original afirmaba "no borra nada
en la máquina"; es falso. El `dd` es inmediato, irreversible y sin snapshot. La escalera de
gates es proporcional a *eso*, y el borrado del disco del sistema ocurre después, en
`lib/base-install.sh` tras su propio `confirm_wipe` (`lib/disk.sh:78-97`).

### Escalera de gates

| # | Peldaño | Qué lo hace imposible por accidente |
|---|---|---|
| 1 | Tarjeta explicativa | Abre información, no la acción |
| 2 | Preflight | Sin red / sin `restic` / sin candidatos ⇒ muere con diagnóstico, sin alternativa degradada |
| 3 | Respaldo verificado | `archfrican-backup verify` + snapshot creado en esta sesión. Única salida: escribir `SIN RESPALDO` completo |
| 4 | Posesión de la passphrase | Ver §7 — verificación de posesión, no transcripción |
| 5 | Elección del destino | Lista por sustracción; muestra LABEL/FSTYPE/uso de cada candidato |
| 6 | Nombre escrito | `escribe BORRAR para formatear el USB <modelo>` |
| 7 | Armado en runtime | `ARCHFRICAN_RESET_ARMED` default `0`; se arma solo tras 3-6 |

### Verificación del respaldo — dueño único (C2, 5-0)

**`archfrican-backup verify` es el único que habla con restic.** El asistente consume códigos
de salida; no reimplementa nada. Razón dura, no estética: la verificación del diseño original
fallaba *abierta* (dispositivo indeterminable ⇒ pasa) mientras `verify` falla *cerrada*
(`same_disk=unknown` ⇒ rc 5). Con dos implementaciones, la insegura es la que queda en el
camino destructivo.

Lo que se queda en `lib/reset.sh`: la relación entre el repo y **el disco que se va a
reinstalar**, que no es necesariamente el de `$HOME` y que `verify` no puede conocer.

`restic check` es **obligatorio** aquí (C1). El argumento del coste era falso: medido, 0,9 s en
un repo local de 820 MB / 50 000 ficheros; "horas" describe `--read-data`, que nunca se corre
por defecto. Lo que sí hay que manejar es que `check` toma lock exclusivo y devuelve **rc 11**
ante un lock rancio de cualquier backup interrumpido, mientras las demás comprobaciones pasan:
rc 11 abre una rama con botón **«Desbloquear el respaldo»** que corre `restic unlock` tras
comprobar si el PID sigue vivo en este host.

### Selección del destino

Candidato ⇔ `TYPE=disk` **Y** (`RM=1` **o** `HOTPLUG=1` **o** `TRAN=usb`) **Y** no
`loop*`/`zram*`/`sr*` **Y** no protegido. El OR porque muchos SSD externos reportan `RM=0`.

**Conjunto protegido** = disco de `/`, `/boot`, `/home`, **y el del repo restic anclado por
`by-id`/serial en el momento de la verificación** (§7, F2). Se excluye por disco entero, nunca
por partición. Si el sistema arranca de un USB, ese disco es removible *y* protegido: la
sustracción lo elimina sin caso especial. Cero candidatos ⇒ muere con el volcado de `lsblk` y
la lista de exclusiones; **nunca degrada a ofrecer el disco del sistema**.

### ISO

Release taggeado, nunca `nightly` (su propio cuerpo dice "Not validated", `iso.yml:127`).
Nombre con fecha (`build-iso.sh:16,47`) ⇒ hay que parsear `browser_download_url` de la API con
`python3` (ya es dependencia dura del menú, `executable_archfrican-actions:19`). Manejar 403
por rate limit anónimo.

Verificación posible: TLS, `Content-Length` vs bytes escritos, tamaño ≥ 300 MiB (la constante
de `iso.yml:62`), y `blkid -o value -s LABEL` casando `^ARCHFRICAN_[0-9]{6}$`
(`build-iso.sh:46`) — esto mata la página HTML de error guardada como `.iso` y la descarga
truncada. **La autenticidad no se puede verificar** (no hay checksum publicado; el único ancla
es el TLS de GitHub). Se dice en pantalla.

Caché en `${XDG_CACHE_HOME:-$HOME/.cache}/archfrican/iso/`, descarga a `.part` con
`-C - --retry 3`, renombrado solo al completar. `df` ≥ 1,1× antes de empezar.

### Grabado

Pre-vuelo: `blockdev --getsize64` ≥ tamaño ISO (si no, negarse **antes** de escribir — un `dd`
truncado deja un USB que parece grabado y no arranca), y desmontar particiones del objetivo.
**Releer modelo+serial inmediatamente antes del `dd` y abortar si cambió**: un replug entre el
gate 6 y la escritura reordena los nombres de kernel (§7, F3).

`ghostty -e sh -c "sudo dd ... status=progress oflag=direct conv=fsync"`, con el rc capturado a
fichero — una terminal que se cierra no informa de nada. Verificación por relectura:
`blockdev --flushbufs` y comparar sha256 del prefijo escrito contra el fichero local.

### Final

No se promete arrancar directo al USB: `efibootmgr --bootnext` no puede apuntar a un
dispositivo sin entrada NVRAM previa. Se ofrece `systemctl reboot --firmware-setup` (ya usado
en `executable_archfrican-secureboot:11`) y se dice que hay que elegir el USB en el firmware.

La tarjeta final **no se titula «USB listo»**: el usuario que va a vender el portátil leería
ahí un permiso para parar, y vendería el disco con sus datos. Se titula `Falta lo importante`,
y abre con `Todavía no se ha borrado nada.`

---

## 6. Nivel 4 — Limpieza profunda (bloqueada)

Tarjeta con tres partes: qué hará, por qué no todavía (le falta el mecanismo de arranque en
modo rescate), y la alternativa (`Restablecer · tus archivos se quedan`). Nunca un `note()` de
error: una notificación efímera se lee como avería.

Cuando la Fase 1 del deep-clean aterrice, este nivel es su trigger — el hueco que su propio
spec difiere a "Fase 3". **`lib/reset.sh` no sourcea `lib/deep-clean.sh`** (§2).

---

## 7. Correcciones obligatorias antes de escribir código

Hallazgos del panel, todos verificados contra el código o reproducidos. Ninguno es opcional.

### Críticos — rutas a pérdida total con todas las puertas satisfechas

**F1 · El preview es ciego a los borrados.** `chezmoi status --include=files` **oculta las filas
`D`**, y `apply --force` sí las ejecuta. `home/.chezmoiremove` tiene 5 rutas hoy y su propia
regla dice que la lista crece con cada eliminación bajo `home/`. La copia previa —única
mitigación, porque el rollback de root no alcanza `@home`— no copiaría nada de eso.
→ **Usar `--include=files,dirs,remove`**, y ejecutar el converge **solo si la copia terminó
bien, verificada por conteo**.

**F2 · El disco del respaldo se desprotege al desmontarse.** El conjunto protegido se deriva de
montajes vivos. `findmnt -no SOURCE --target <ruta-inexistente>` devuelve vacío con rc=1, así
que tras desenchufar el disco de respaldo —cosa que el propio flujo pide, para liberar el
puerto— reaparece como candidato de destino y el `dd` lo sobrescribe.
→ **Anclar el `by-id`/serial del disco del repo en el momento de la verificación** y prohibirlo
como destino durante toda la sesión; además, sondear el destino en busca de un repo restic
(`config` + `data/`) antes de escribir.

### Altos

**F3 · El filtro no distingue un pendrive vacío del disco de datos**, y el pre-vuelo desmonta lo
que encuentre — la última señal de que ahí había algo. El objetivo se referencia por nombre de
kernel, que es inestable ante replug.
→ Mostrar LABEL/FSTYPE/uso de cada candidato; clave estable (`by-id`); relectura de serial
antes del `dd`.

**F4 · `rs_subset_of` acota nombres, no la clausura de `-Rns`.** `prune_candidates` garantiza
que los paquetes *nombrados* no tienen dependientes, pero `-s` arrastra la clausura: el usuario
aprueba 14 nombres y se ejecutan ~80 desinstalaciones. Y `-n` borra los `/etc` editados a mano
**sin dejar `.pacsave`**.
→ Obtener la clausura real con `--print`, correr guard **y** subset sobre ella, y usar **`-Rs`
sin `-n`**.

**F5 · El guard del kernel está muerto y falla abierto.** Reproducido en la máquina del usuario:
`pacman -Qqo "/usr/lib/modules/$(uname -r)/vmlinuz"` → `error: No package owns …`, salida vacía,
rc=1, porque el kernel en ejecución (6.18.39) es anterior al instalado (6.18.50) — el estado
normal tras actualizar sin reiniciar. Además la premisa es falsa: ningún kernel ha estado nunca
en `packages/*.txt` (se instalan en `modules/00-base.sh:56`), así que la puerta `managed.txt`
(`lib/manifest.sh:60`) ya los excluye.
→ Fallar cerrado: si el sondeo no resuelve, `rs_guard_never_remove` devuelve rc≠0 y el llamador
aborta la poda (no `die` — §2 prohíbe que `lib/reset.sh` mate al asistente). Preferir además el
patrón de lista literal de `lib/deep-clean.sh:49-61`, estrictamente más fuerte que un sondeo
dinámico.

**F6 · `db.lck` deja al usuario sin salida sin comandos.** Si el converge muere a golpes durante
`pacman -S`, todo pacman falla después: converge, poda, update y doctor. No hay ni un manejo de
`db.lck` en el repo.
→ Detectarlo y ofrecer liberarlo tras comprobar que ningún pacman vive.

**F7 · El Nivel 2 sin `terminal = true`** se cuelga pidiendo sudo sin TTY (ya incorporado en §2).

**F8 · El reset no puede borrar `$PHASE2_STATE`.** Comparte directorio con el marcador de
`lib/resume-guard.sh:20-23` y el `ConditionPathExists=!` de `templates/archfrican-resume.service:23`,
cuyo `systemctl disable` es best-effort. Borrarlo re-arma un `install.sh` **completo** —no
`--update`— sin TTY en el siguiente arranque, y ese camino sí re-aplica identidad.
→ Invariante explícita en el código.

### Medios

**F9 · Los archivos que regenera `home/run_after_99-apply-theme.sh.tmpl`** (`fuzzel.ini`,
`gtklock/style.css`, `gtk.css`, `qt6ct.conf`, colores de waybar/swaync) están en
`.chezmoiignore` y son invisibles a `chezmoi status`. "Tus ajustes se quedan" es falso para
exactamente los que un usuario que personaliza edita a mano. → Nombrarlos en el preview.

**F10 · La passphrase en claro junto al repo destruye el cifrado.** `executable_archfrican-backup:33`
la genera con `umask 077` + `chmod 600` deliberadamente; escribirla en el USB de destino
convierte un disco robado en el `$HOME` completo. → Nunca en el destino.

**F11 · El gate de la passphrase es impasable como transcripción.** Son 32 caracteres aleatorios
(`head -c 24 /dev/urandom | base64`): pedir retipearlos produce cinco fallos y empuja al escape
`SIN RESPALDO`. → Verificar **posesión**: que el usuario guarde el fichero en otro medio y el
asistente lo lea de vuelta desde ahí.

**F12 · El cálculo de antigüedad falla abierto.** Con el reloj atrasado, un snapshot viejo da
edad negativa ⇒ "fresco" ⇒ autoriza el borrado. → Edad negativa o absurda (>3650 días) ⇒ `stale`.

**F13 · El lock necesita más que ampliar el grep.** El `trap 'rm -rf "$LOCKDIR"' EXIT`
(`bin/archfrican-update:70`) es incondicional: copiado tal cual, un reset que pierda una carrera
borraría el lock ajeno. → Liberar solo si `$LOCKDIR/pid == $$`. Y ampliar el grep de `:61` a
`archfrican-(update|reset)`, sin lo cual `archfrican-update` declara rancio un reset vivo y lo
pisa: dos converges y un `pacman -Syu` simultáneos.

**F14 · Snapshots desalojables.** La config `root` de snapper nunca recibe `NUMBER_LIMIT` (solo
`home`, `modules/50-snapshots.sh:76-82`) ⇒ defaults 50/10. Sin `--userdata important=yes`, la
ráfaga de snap-pac del converge puede desalojar el punto de retorno que «Deshacer» promete.

**F15 · La copia de dotfiles debe ser write-once.** Tras un `chezmoi --force` parcial, las
ediciones locales ya no existen: repetirla guardaría la versión del repo sobre la copia buena.
El resume nunca puede re-ejecutarla.

**F16 · El sello de reanudación debe registrar "converge completado", no el índice de paso.**
Reanudar en "poda" tras un converge muerto a medias poda contra un manifiesto viejo — lo que
§4 prohíbe. Sin esa prueba, el resume reempieza en el converge.

### Interacciones

`archfrican-update-check.timer` es horario y está vivo: puede disparar durante un converge y
robar el lock. Además del grep, silenciar su notificación mientras el lock esté tomado.
`archfrican-backup.timer` (`Persistent=true`) puede fotografiar un `$HOME` a medio reescribir.
Y no hay inhibidor de suspensión: `systemd-inhibit --what=sleep:shutdown:idle` alrededor del
flujo, dentro de `rs_lock`.

---

## 8. «Deshacer» — la promesa honesta (C4, 5-0)

Un snapshot de snapper cubre `@`. El layout es `@ @home @log @pkg @.snapshots`
(`lib/base-install.sh:82`) y `/boot` es la ESP FAT (`:90`). Entonces **no** revierte: los
dotfiles y las estampas de módulos (viven en `@home`), `grub.cfg` (la ESP no es btrfs), ni
`/var/log` y la caché de pacman (subvolúmenes aparte). Y deja el sistema descuadrado —paquetes
de antes, estampas de después—, un estado que `drift_modules` **no puede detectar** porque
compara repo contra estampas, no estampas contra realidad.

Tarjeta (12 líneas, ninguna >44 columnas):

```
Volver atrás

Recupero tus programas y los ajustes del
sistema tal como estaban. Hay que reiniciar.

Dos cosas no vuelven solas:
  ·  Tus ficheros de configuración: te los
     copio a Documentos al terminar.
  ·  Al arrancar te pediré «Reparar» una vez
     para dejar todo en hora.

Tus fotos y documentos siguen intactos.
```

Esa promesa **exige mecanismo**, no solo texto:
- Al hacer rollback, copiar `~/.local/state/archfrican/reset-<ts>/dotfiles/` a
  `~/Ajustes-anteriores-<fecha>/`. Sin eso la frase es mentira.
- `archfrican_rollback_to` deja una miga en `@home` (sobrevive al swap de root) que
  `archfrican-reset` convierte al arrancar en «Termina de deshacer · 1 paso».
- **No ofrecer «Deshacer»** si `rs_snapshot` falló, si el root no es Btrfs, o con batería
  crítica: la ventana de `lib/rollback.sh:92-99` es la única forma de que el equipo no arranque.

`grub.cfg` no se menciona en la tarjeta: no revertirlo no tiene consecuencia observable, y
nombrarlo solo asusta.

---

## 9. Confirmaciones (C6, 5-0)

`confirm()` (`archfrican-common.sh:10-14`) imprime `Sí, …` como **primera** línea y fuzzel
preselecciona la primera: un Enter perdido confirma. Afecta a dos mecanismos distintos, no uno:
el helper lo usan **5 scripts** (`secureboot:15`, `rollback:29`, `plymouth:32`, `versions:85`,
`tpm-unlock:28`), y `actions.toml.tmpl` lleva el `printf` incrustado en **3 entradas** (cerrar
sesión, reiniciar, apagar).

**Añadir `confirm_destructive()` con `Cancelar` primero**, sin tocar los llamadores existentes
en el mismo commit: invertir lo benigno entrena el dedo al revés, y `case "Sí,"*`
(`archfrican-common.sh:13`) depende del orden.

**Reservar las mayúsculas para una sola cosa**: el texto que hay que teclear. Seis gritos
(`SE PIERDE TODO`, `TUS ARCHIVOS SE QUEDAN`, …) hacen que el usuario deje de oírlos.

---

## 10. Alcance — lo que se corta

Decidido con el usuario (2a). **Fuera:**

- **El job `reset-safety-gate`.** Su grep central es auto-satisfactorio: prohíbe `of=/dev/sd`
  literal, pero el código escribe `of=/dev/$dev` — una variable. Nunca aparece, ni en código
  correcto ni en código catastrófico: el gate pasa siempre. `deepclean-safety-gate`
  (`ci.yml:65-79`) sí funciona porque `DEEPCLEAN_DELETE_SUBVOLS=(...)` es un literal que el
  código contiene. En su lugar: una línea añadiendo los tests nuevos al job `unit-logic`.
- **El checksum de la ISO en CI.** Es cadena de suministro, no reset. Un `.sha256` del mismo
  Actions sobre el mismo TLS no añade raíz de confianza; añade tres sitios donde el par puede
  descuadrarse. `rs_iso_looks_valid` ya mata los dos fallos reales.
- **`note()` con urgencia.** Toca una función que consumen 29 archivos para un solo llamador
  nuevo. `notify-send -u critical` local en `archfrican-backup` resuelve lo mismo.
- **`SuccessExitStatus=2` + su migración + el mapeo rc 3→2.** Empezar con 0/1.

**Dentro, y explícitamente conservado:** `archfrican-backup restore` de verdad. Cortarlo dejaba
al usuario escribiendo `restic restore` a mano justo después de reinstalar, que es donde la
premisa de "sin comandos" más importa.

`restore` restaura **siempre a un directorio de staging** (`~/Restaurado-<ts>/`), nunca sobre
`$HOME`: (a) `restic restore` sobrescribe sin deshacer; (b) un fallo a mitad sobre un `$HOME`
vivo deja mitad viejo / mitad nuevo indistinguibles; (c) hay ficheros de sesión abiertos; (d)
el repo ya tomó esta decisión en `archfrican-versions:65-89`. Mover a `$HOME` es un segundo
paso explícito con `cp -a --backup=numbered`.

---

## 11. Arreglos previos, en commits aparte

Decidido con el usuario (3a): van **antes** de la feature, cada uno con sus tests.

1. **`load()` mata el script en silencio** (`executable_archfrican-backup:12-15`). La última
   orden es `[ -r "$passfile" ] && export …`; si el fichero no es legible devuelve 1, la
   función devuelve 1, y bajo `set -euo pipefail` `errexit` mata `now`/`list`/`restore` sin
   imprimir nada. **Reproducido en aislamiento: exit=1, sin salida.** → `return 0` explícito +
   `note` cuando falta la clave.
2. **`now` miente con su exit code** (`:40-44`). El fallo está dentro de un `if`, así que
   `set -e` no se activa y el script sale 0. Cadena: el timer queda `active(exited)`,
   `check_failed_units` (`lib/health.sh:16-23`) nunca la ve, y el chequeo semanal
   (`modules/70-hygiene.sh:62-83`) da verde sobre un respaldo roto hace semanas. → Salir 1 y
   escribir log a `$XDG_STATE_HOME/archfrican/backup.log` en vez de `/dev/null`.
3. **`archfrican-backup verify`** — subcomando nuevo, contrato de exit codes 0-5 y stdout
   `clave=valor` con las mismas claves en todos los casos. Sin fuzzel, sin ghostty.
4. **El grep del lock** (`bin/archfrican-update:61`) + la liberación condicional del trap (F13).
5. **`confirm_destructive()`** (§9).
6. **El guard del kernel** (F5), si se conserva algún sondeo dinámico en el repo.

---

## 12. Tests

Cuatro archivos nuevos, registrados en `unit-logic` (`ci.yml:327-361`). Patrones existentes:
fixture + contador de invocaciones (`tests/unit/deep-clean.sh:32-49`), stubs de `pacman`/`sudo`
(`tests/unit/manifest.sh:27,75-80`), stub en PATH (`tests/unit/weather.sh:30-43`), transcripción
de llamadas (`tests/unit/rollback.sh:48-88`).

**El test imprescindible**, si solo pudiera existir uno: `rs_list_usb_targets` con el disco del
sistema en `sdc` y `sdc RM=1 HOTPLUG=1 TRAN=usb` (arranque desde USB), asertando salida
`sdb sda` y **ni una mención de `sdc`**. Es el único fallo que destruye sin consentimiento: los
otros seis peldaños no lo cubren, porque el nombre tecleado en el gate 6 es el que la lista
mostró — si la lista está mal, la confirmación confirma el error con toda ceremonia.

Otros que atrapan regresiones reales:
- `rs_dotfile_edits` con fixture que incluye `D` y una ruta con espacios; y **rc≠0, nunca lista
  vacía, si falta `--source`** (una lista vacía silenciosa significa "nada que respaldar" y el
  `--force` destruye).
- `rs_subset_of` con la clausura real, no con los nombres.
- `rs_remove_packages`: sin args ⇒ rc 2 y cero invocaciones de pacman; con args, argv capturado
  **sin `--noconfirm`** y **sin `-n`**.
- `rs_verify_backup` falso cuando el conjunto de snapshots posterior == anterior.
- Frontera de antigüedad: 6d23h ⇒ ok, 7d01h ⇒ stale, futuro ⇒ stale.
- Sin armar, `rs_write_iso` ejecuta **cero** comandos reales.
- Gate `reset-menu-shape` (python `tomllib`, ya dependencia): cada `text` ≤ 41 caracteres, la
  puerta es `run =` y no `submenu =`, y cada `run` apunta a un fichero existente.

**Cubrible con esfuerzo, y vale la pena:** `losetup` sobre un archivo disperso de 4 GiB en
`tests/e2e/`, con `rs_write_iso` **armado** contra él y `rs_verify_written` de verdad. Convierte
la pieza más peligrosa en aserción real sin hardware.

**Descubierto, declarado:** que ese USB arranque en un firmware concreto; que fuzzel
preseleccione la primera línea (se testea el dato —`Cancelar` es la línea 1—, no el widget);
que el usuario lea la tarjeta.

---

## 13. Accesibilidad

`archfrican-a11y:55` ("Texto más grande") solo escribe
`org.gnome.desktop.interface text-scaling-factor`, que **fuzzel no honra**: su fuente viene de
`templates/fuzzel.ini:5`, generada por `theme-switch`. Quien pidió texto grande lee las
advertencias de pérdida total a 14 px. Fuera del alcance de esta feature arreglarlo; dentro,
mitigarlo: cada `text` cabe sin elipsis y ninguna información crítica depende de la segunda
línea.

**Orca no ve fuzzel** (no expone AT-SPI): un usuario ciego no puede usar ninguna de estas
pantallas. Mitigación gratuita: los cuatro niveles se invocan por argumento
(`archfrican-reset reparar|restablecer|preparar|limpieza`), recorribles en terminal.

`executable_archfrican-rollback:16,32,36` usa **voseo** contra el tuteo del resto; el Nivel 2
desemboca justo ahí y el cambio de persona se nota. Corregir en el mismo pase.

---

## 14. Riesgos que no se eliminan, solo se declaran

- Las ediciones a dotfiles se pierden salvo por la copia previa; el rollback de root no las
  alcanza.
- Un rollback deja las estampas desincronizadas; el remedio es «Reparar», y hay que cablearlo,
  no solo documentarlo (§8).
- `/boot`, `@log` y `@pkg` quedan fuera de cualquier snapshot.
- En raíz no-Btrfs el Nivel 2 no tiene vuelta atrás de ningún tipo.
- La autenticidad de la ISO descargada no se puede verificar hoy.
- Un corte eléctrico dentro de la ventana de `lib/rollback.sh:92-99` deja la máquina sin
  arrancar; solo se sale con un USB en vivo. Es raro y ya existe hoy.
