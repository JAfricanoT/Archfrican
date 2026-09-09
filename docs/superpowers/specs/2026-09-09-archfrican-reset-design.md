# Reparar y restablecer sin comandos — diseño

## Qué se pidió y qué se entrega

El usuario pidió que el procedimiento de factory reset —conservando o no sus archivos— se
simplificara hasta que "no tenga que estar metiendo comandos". `docs/RECOVERY.md` §10
documentaba un procedimiento que preservaba `/home` y era falso; corregido en `2ac3a20`.

**Este documento es la segunda versión.** La primera (`fd5b9cc`) especificaba un asistente de
cuatro niveles con `lib/reset.sh`, binario propio, menú propio y cuatro ficheros de test. Un
comité de cinco revisores —implementador, verificador de hechos, privilegios, dominio y
abogado del diablo— la desmontó. El resumen de por qué está en §7; lo que sobrevive es esto:

**Dos entradas de menú sobre código que ya existe, más seis arreglos a bugs vivos.** Sin
subsistema nuevo. El grueso del valor con una fracción de la superficie.

---

## 1. Lo que ya existe y no hay que construir

`bin/archfrican-update` ya tiene `--converge` (`:33`), que re-aplica config y dotfiles sin
actualizar paquetes, y `do_prune()` (`:312`), que poda con `prune_candidates`
(`lib/manifest.sh:52-68`) en el orden correcto: converge primero (`:375`), poda después
(`:405`). Ya tiene lock con clave de PID (`:53-70`), pre-snapshot (`:149`), changelog, y
entrada en el menú de acciones (`actions.toml.tmpl:35-42`).

El delta real entre "lo que hay" y "reparar / restablecer sin comandos" son cuatro cosas:

1. `FORCE=1`, para ignorar las estampas cuando el sistema está roto pero el repo no cambió.
2. Copiar a un lado los dotfiles editados **antes** de que el converge los pise.
3. Marcar el snapshot para que se distinga de los automáticos.
4. Dos entradas de menú con el texto correcto.

---

## 2. Las dos entradas

| Texto (`actions.toml.tmpl`) | Cols | Ejecuta |
|---|---|---|
| `Reparar el sistema  ·  no borra archivos` | 40 | `archfrican-update --repair` |
| `Restablecer  ·  tus archivos se quedan` | 38 | `archfrican-update --repair --prune` |

Ambas con `terminal = true` y el envoltorio `sh -c '…; printf "\n(enter para cerrar) "; read -r _'`
que ya usan `:35-42`: el flujo pide contraseña de sudo y el Y/N de pacman, y sin TTY se cuelga
o muere mudo.

Van junto a `Revertir actualización (rollback)…` (`:196`), donde ya está agrupada la
recuperación — no al principio del hub, que empieza por `Bloquear pantalla`.

**Restricción dura de anchura.** `templates/fuzzel.ini:9-10` fija `width=46` y `lines=12`, y
fuzzel trunca las filas de `--dmenu` en vez de envolverlas. Con iconos activos (`:8`) el
presupuesto útil ronda los **41 caracteres**; los dos textos de arriba caben (40 y 38).

> El nombre "Restablecer a fábrica · conserva tus archivos" se descartó por longitud: son 47
> caracteres y se trunca a `Restablecer a fábrica  ·  conserva tus ar`. La salvedad no
> desaparece —se corta a mitad de palabra—, pero truncar una promesa de conservación en la
> entrada vecina a una destructiva no es aceptable. "Fábrica" además es, en vocabulario de
> consumo, el término del borrado total.

---

## 3. `archfrican-update --repair`

Flag nuevo en el parser que ya existe (`:31-38`). Implica `--converge`, y añade:

```
rs_pacman_unlocked          || ofrecer liberar db.lck            (§5.6)
rs_dotfile_edits            → preview + copia write-once          (§5.1)
pre_snapshot con -u important=yes                                 (§5.5)
FORCE=1 en el entorno del converge
```

`FORCE=1` y no selectivo por drift: `drift_modules` (`lib/converge.sh:68-75`) compara *inputs
del repo* contra el hash estampado, así que un sistema roto con el repo intacto no muestra
drift y el converge lo saltaría todo (`lib/phase2.sh:58`). Reparar existe justo para el caso
"el estampado miente".

No hace `git pull`: eso es `--run`. Reparar re-aplica **el clon que ya tienes**, y la salida lo
dice mostrando el commit (`git -C "$ROOT" log -1 --format='%h %s'`).

`--repair --prune` es el segundo nivel: lo anterior más `do_prune`, ya corregido según §5.2.

**Puerta condicional.** Si `rs_dotfile_edits` devuelve 0 ficheros, ejecuta sin preguntar. Si
devuelve N>0, una pantalla que los nombra antes de seguir. El permiso se pide solo cuando hay
algo que perder.

---

## 4. Lo que se descarta, y por qué

**El Nivel 3 ("preparar borrado total": respaldar, descargar la ISO, grabar el USB).**

No existe ningún release taggeado: `git tag -l` da `nightly` y dos `backup/*`; `gh release list`
da una sola entrada, la prerelease `nightly` del 2026-07-19. El diseño prohibía usar nightly
—su propio cuerpo dice "Not validated — use a tagged release" (`iso.yml:127`)— y prohibía
degradar. **Habría muerto en su segundo peldaño el 100 % de las veces.**

Además su valor real eran dos cosas —"verifica tu respaldo antes" y "no elijas el disco
equivocado"— envueltas en reimplementar `dd` con más pasos: parseo de la API de GitHub, caché
`.part`, `df ≥ 1,1×`, regex de etiqueta duplicada desde `build-iso.sh:46`, relectura de serial,
verificación por sha256. Cuatro dependencias externas nuevas en un camino destructivo, para
llegar a un instalador que ya tiene su propio `confirm_wipe` (`lib/disk.sh:78-97`).

Se retoma cuando exista un release taggeado, y entonces como checklist que verifica el respaldo
y lista los candidatos, no como grabador.

**El Nivel 4 (limpieza profunda, bloqueada).** `docs/RECOVERY.md` ya dice que deep-clean está
diseñado, sin cablear e inalcanzable. Una entrada permanente que no hace nada, en un menú de 12
filas y junto a las destructivas, sienta el peor precedente posible ahí: que una entrada de
este menú puede no hacer nada.

**Nota de prioridad.** Deep-clean *es* lo que se pidió: reset conservando `/home`, sin USB y sin
comandos. Su Fase 0 está construida (`lib/deep-clean.sh`) y su Fase 1 especificada desde
2026-07-03 sin implementar. Terminar esa fase aporta más que cualquier envoltorio alrededor de
su ausencia.

---

## 5. Los arreglos — cada uno su commit, todos antes de las entradas de menú

### 5.1 · La copia previa de dotfiles (la única pérdida silenciosa que queda)

Cualquier converge ejecuta `chezmoi init --apply --force --source "$REPO_ROOT/home"`
(`lib/phase2.sh:244`). `--force` sobrescribe sin preguntar todo dotfile gestionado con
ediciones locales, y ejecuta los borrados de `home/.chezmoiremove` (5 rutas hoy; su propia
regla dice que la lista crece con cada eliminación bajo `home/`).

**Nada de esto lo revierte un rollback**, porque vive en `@home` y `lib/rollback.sh` solo
intercambia el subvolumen root. La copia previa es la única red.

- Listar con **`chezmoi status --include=all --source "$REPO_ROOT/home" -p absolute`**.
  `--include=files,dirs,remove` **oculta `symlinks` y `scripts`** —verificado—, y el repo tiene
  `home/dot_local/bin/symlink_theme-switch.tmpl` y `home/run_after_99-apply-theme.sh.tmpl`.
  `all` es el default y es el correcto.
- **Columna 2** (lo que hará `apply`), códigos `A`/`D`/`M`. La columna 1 depende del boltdb
  persistente y no se debe usar.
- `-p absolute` evita parsear rutas con espacios: `awk '{print $2}'` las parte,
  `cut -c4-` no.
- **Fallo cerrado con matiz:** un `--source` inexistente da rc=1, pero un `--source` que existe
  y está **vacío** da **rc=0 con lista vacía** — el silencio peligroso. Comprobar que el
  directorio contiene entradas antes de aceptar una lista vacía.
- Copia **write-once** a `$XDG_STATE_HOME/archfrican/reset-<ts>/dotfiles/`, con marcador
  `.done`. Tras un converge parcial las ediciones ya no existen: repetir la copia guardaría la
  versión del repo sobre la buena.
- **El converge solo corre si la copia terminó**, verificado por conteo.
- Los ficheros que regenera `run_after_99-apply-theme.sh.tmpl` (los de `.chezmoiignore`) son
  invisibles a `chezmoi status` incluso con `--include=all` —verificado— y también se pierden.
  Se copian desde una lista literal y se nombran en el preview.

### 5.2 · `-Rns` → `-Rs`, y enseñar la clausura real

`bin/archfrican-update:320` corre hoy `sudo pacman -Rns "${cand[@]}"`. Dos problemas, en código
que ya se ejecuta:

- **`-n` borra los ficheros de configuración del paquete sin dejar `.pacsave`.** El comentario
  de esa línea ("pacman itself refuses unsafe removals") es cierto para dependencias rotas y no
  dice nada de `/etc`. → **`-Rs`**.
- **`-s` arrastra la clausura de dependencias**, así que el usuario aprueba N nombres y se
  ejecutan bastantes más. `prune_candidates` garantiza que los *nombrados* no tienen
  dependientes (`lib/manifest.sh:65`), no que la clausura sea segura.
  → Previsualizar con **`pacman -Rs --print`** sobre la lista completa de una sola vez.
  (`-Rns --print` **no existe**: pacman rechaza `--nosave` con `--print`.)

La comprobación **no puede ser "la clausura ⊆ managed.txt"**: la clausura contiene por
construcción dependencias arrastradas que nunca estuvieron en el manifiesto, así que ese
subconjunto fallaría siempre y la poda no correría nunca. La regla computable es de
violaciones: **rechazar si algún miembro de la clausura es explícito fuera de los candidatos,
está en `manifest.txt`, o está en la lista literal de abajo.**

```sh
RS_NEVER_REMOVE=(base linux-cachyos linux-cachyos-headers linux-lts linux-lts-headers
                 linux-firmware btrfs-progs grub efibootmgr sudo networkmanager systemd
                 pacman zram-generator cryptsetup mkinitcpio niri sddm)
```

Literal, nunca computada — el patrón de `DEEPCLEAN_DELETE_SUBVOLS` (`lib/deep-clean.sh:53`). El
sondeo dinámico del kernel que la primera versión proponía **falla abierto**: en esta máquina
`pacman -Qqo "/usr/lib/modules/$(uname -r)/vmlinuz"` devuelve `error: No package owns`, stdout
vacío y rc=1, porque el kernel en ejecución tiene distinto pkgrel que el instalado — el estado
normal tras actualizar sin reiniciar.

`niri` está hoy en `managed.txt` con `Required By: None`: si algún día sale de `packages/*.txt`,
es candidato legítimo y `-Rs` se llevaría el escritorio. De ahí la lista.

### 5.3 · `load()` mata el script en silencio

`home/dot_local/bin/executable_archfrican-backup:12-15`: la última orden de la función es
`[ -r "$passfile" ] && export RESTIC_PASSWORD_FILE="$passfile"`. Si el fichero no es legible
devuelve 1, la función devuelve 1, y como se invoca como comando simple (`:34`, `:38`, `:45`,
`:46`) bajo `set -euo pipefail` (`:6`), `errexit` mata el script. **Reproducido en aislamiento:
exit=1, sin imprimir nada.**

Duele justo donde más importa: sistema recién reinstalado, el usuario recuperó `restic-repo` de
una nota pero no tiene `restic-pass` a mano, y `archfrican-backup restore` se cierra sin decir
palabra. → `return 0` explícito y un `note` cuando falta la clave.

### 5.4 · `now` miente con su exit code

`:40-44`: el fallo está dentro de un `if`, así que `set -e` no se activa y el script sale 0. El
timer queda `active(exited)`, `check_failed_units` (`lib/health.sh:15-22`) nunca lo ve, y el
chequeo semanal (`modules/70-hygiene.sh`) da verde sobre un respaldo roto hace semanas.

→ Salir 1 al fallar, y escribir la salida de restic a
`$XDG_STATE_HOME/archfrican/backup.log` (append con timestamp, recortado con `tail`) en vez de
`/dev/null`, para que el fallo sea diagnosticable.

### 5.5 · El snapshot de retorno

`pre_snapshot` (`bin/archfrican-update:149`) ya usa `--cleanup-algorithm number`. Añadir
`-u important=yes` **no lo protege**: mueve el snapshot a un cubo independiente cuyo límite por
defecto es 10, que varios resets desalojan igual. Y `NUMBER_CLEANUP` **por defecto es `no`**,
así que hay que leer la config real de `root` antes de asumir que el algoritmo corre.

Lo que sí se hace: descripción reconocible ("antes de reparar" / "antes de restablecer"), para
que `archfrican-rollback` —que lista `número · fecha · descripción` (`:24`)— la muestre. Sin
eso, "Deshacer" pide al usuario adivinar un número.

### 5.6 · `db.lck`

Si el converge muere a golpes durante `pacman -S`, todo pacman falla después: converge, poda,
update y doctor. **No hay ni un manejo de `db.lck` en el repo**, así que no hay salida sin
escribir comandos — lo contrario de lo que esta feature promete.

→ `rs_pacman_unlocked`: rc 0 libre, rc 1 bloqueado con un pacman vivo, rc 2 bloqueado y
huérfano (ofrecible al usuario). Se comprueba antes del converge.

### 5.7 · El lock

`take_lock` (`bin/archfrican-update:54-67`) filtra el dueño con `grep -q 'archfrican-update'`
(`:61`). Como `--repair` es el mismo binario, este caso concreto está cubierto — pero el grep
sigue siendo frágil ante cualquier consumidor futuro, y hay dos correcciones reales:

- El `trap 'rm -rf "$LOCKDIR"' EXIT` (`:70`) se instala **después** de `take_lock || die`, así
  que perder la carrera nunca llega al trap: el riesgo que la primera versión describía no
  existe tal como lo describía. Aun así, liberar solo si `$LOCKDIR/pid == $$` es correcto y
  barato.
- `LOCKDIR="${XDG_RUNTIME_DIR:-/tmp}/…"` (`:53`): dos invocaciones, una con `XDG_RUNTIME_DIR` y
  otra sin él, usan lockdirs distintos y **ambas ganan**. Anclar a una ruta única.

### 5.8 · `restore` de verdad

`:46` no restaura: abre una terminal, lista snapshots e imprime el comando que el usuario
tendría que teclear. Es exactamente donde "sin comandos" más importa — después de reinstalar,
en un sistema nuevo, con el usuario nervioso.

Restaura **siempre a un directorio de staging** (`~/Restaurado-<ts>/`), nunca sobre `$HOME`:
`restic restore` sobrescribe sin deshacer; un fallo a mitad sobre un `$HOME` vivo deja mitad
viejo y mitad nuevo indistinguibles; y hay ficheros de sesión abiertos. Mover a `$HOME` es un
segundo paso explícito con `cp -a --backup=numbered`, que deja `archivo.~1~` en cada colisión.

En el caso post-reinstalación `$HOME` está vacío y el merge es no-op, así que el staging no
cuesta nada.

*(Precedente: `archfrican-versions` restaura junto al original con sufijo, no sobre él. El
principio es el mismo aunque el mecanismo difiera.)*

---

## 6. El riesgo que ninguna versión del diseño vio: rollback y kernel

**Esto no es del código nuevo. `archfrican-rollback` ya está desplegado.**

`/boot` es la ESP vfat (`lib/base-install.sh:90`) y contiene los `vmlinuz` e `initramfs` de
todos los kernels. `/usr/lib/modules` vive en `@`. Ningún snapshot de root cubre `/boot`.

Un rollback que cruce una actualización de kernel arranca el `vmlinuz` **nuevo** contra un `@`
cuyo `/usr/lib/modules/<versión>` no existe. En esta máquina el desajuste ya está presente sin
rollback ninguno:

```
kernel corriendo:  6.18.50-1-lts
módulos en disco:  6.18.50-2-lts, 7.2.3-1-cachyos
```

→ Antes de ofrecer «Deshacer», comprobar que el snapshot contiene los módulos del `vmlinuz` que
hay en `/boot`. Si no, negarlo o encadenar reinstalación del kernel + `mkinitcpio -P`.

Va en su propio commit, independiente de esta feature, porque arregla algo que ya puede dejar
un equipo sin arrancar.

---

## 7. Por qué la primera versión no se construye

Registro de lo que encontró el comité, para que no se re-derive:

- **Sin release taggeado** ⇒ el Nivel 3 muere en su segundo peldaño siempre (§4).
- **El conjunto protegido salía vacío en instalación cifrada.** `findmnt -no SOURCE --target /`
  devuelve `/dev/mapper/root[/@]`: hay que quitar el sufijo y recorrer LUKS→partición→disco. El
  diseño decía "cero candidatos ⇒ muere" y nada sobre "cero protegidos ⇒ muere". La función que
  impedía grabar sobre el disco de sistema **fallaba abierta en la configuración por defecto**.
- **El peldaño de armado no era un gate**: `ARCHFRICAN_RESET_ARMED` se auto-armaba en el mismo
  proceso que protegía, al contrario que `ARCHFRICAN_DEEPCLEAN_ARMED`, que es un opt-in externo
  con su default afirmado en CI (`ci.yml:72-74`).
- **`ARCHFRICAN_STATE_DIR` es override por entorno** (`lib/manifest.sh:13`), así que la lista
  que llega a `sudo pacman -Rs` la decide el entorno. Vale igual para `--prune` hoy.
- **Borrar `$PHASE2_STATE` re-arma una ventana `NOPASSWD`**: ese directorio contiene
  `resume-stopped`, que es el `ConditionPathExists=!` de `templates/archfrican-resume.service:23`.
  Invariante: el reset nunca borra ese directorio.
- **El `dd` especificado no llevaba `bs=`** — 450× más lento, medido. Una ISO habría tardado
  más de 15 minutos sobre SSD.
- **`systemd-inhibit --what=sleep:shutdown:idle` no cubre el cierre de tapa**
  (`LidSwitchIgnoreInhibited` es `yes` por defecto), y no existe como "toma el lock y sal": solo
  envuelve un comando.
- **`restic unlock` sin `--remove-all` no quita locks de otro hostname con menos de 30 min**, así
  que su rc 0 no significa desbloqueado.
- **7 de 92 afirmaciones del documento fallaban**, cinco por número de línea desplazado. Ninguna
  de las trece que sostenían una garantía de seguridad.

---

## 8. Tests

Al job `unit-logic` (`.github/workflows/ci.yml:375-414`). Patrones existentes: stubs en PATH
(`tests/unit/weather.sh:30-43`), stubs de `pacman`/`sudo` (`tests/unit/manifest.sh:27,75-80`),
transcripción de llamadas (`tests/unit/rollback.sh`).

| Test | Regresión que atrapa |
|---|---|
| `chezmoi` stub que emite `D`, `A`, un symlink y una ruta con espacios ⇒ se listan y copian todos | La pérdida silenciosa de §5.1 |
| `--source` vacío ⇒ rc≠0, **nunca lista vacía** | El silencio peligroso |
| Clausura con un explícito ajeno ⇒ rechazo con el nombre | §5.2, lo que hoy borraría de más |
| Clausura con `niri` ⇒ rechazo | La lista literal |
| Argv de `pacman -R` **sin `-n`** y **sin `--noconfirm`** | El bug vivo de `:320` |
| `now` con restic stub que falla ⇒ **rc 1** y log no vacío | §5.4 |
| `load()` sin `restic-pass` ⇒ mensaje y no muerte muda | §5.3 |
| `restore`: el `--target` no es `$HOME`; el merge usa `--backup=numbered` | §5.8 |
| Snapshot con módulos desajustados ⇒ «Deshacer» no se ofrece | §6 |
| Cada `text` de las entradas nuevas ≤ 41 caracteres | La truncadura |

---

## 9. Lo que no se garantiza

- Las ediciones a dotfiles se pierden salvo por la copia previa; ningún snapshot de root las
  alcanza.
- `/boot`, `@log` y `@pkg` quedan fuera de cualquier snapshot.
- En raíz no-Btrfs no hay vuelta atrás de ningún tipo.
- Un rollback deja las estampas desincronizadas; el remedio es «Reparar», que las ignora.
- La clausura que `pacman -Rs --print` previsualiza se **recalcula** al ejecutar: lo aprobado y
  lo ejecutado pueden divergir si la base de paquetes cambia entre medias.
