# Deep clean — Fase 1: mecanismo de arranque de rescate (diseño)

## Contexto

Fase 0 (mergeada a `main`, `docs/superpowers/plans/2026-07-03-deepclean-fase0.md`) construyó `lib/deep-clean.sh`
como andamiaje puro en modo dry-run: todas las funciones `dc_*` existen, gateadas por `DC_GO`/
`ARCHFRICAN_DEEPCLEAN_ARMED`, pero nada de eso es alcanzable desde ningún lado — no hay forma real de
llegar a ejecutarlas fuera de un test.

Fase 1, según el plan completo aprobado (`docs/superpowers/plans/quiero-que-mejoremos-como-frolicking-peach.md`),
construye el **mecanismo de arranque real**: el hook de mkinitcpio, la entrada de GRUB persistente y
condicional, el armado/desarmado, el intercambio atómico de subvolúmenes, y el guardado de estado para
reintentos. Este documento resuelve las decisiones operativas que el plan original dejó a nivel de
arquitectura (no de implementación), producto de una investigación de las convenciones reales del repo
(`lib/base-install.sh`, `lib/grub.sh`, `docs/RECOVERY.md`) y de una sesión de brainstorming con el usuario.

**Decisiones ya tomadas con el usuario en esta sesión:**
- **Mecanismo de acceso a pacman/red**: el hook de rescate NO empaqueta pacman/NetworkManager/keyring dentro
  del propio initramfs (sería enorme y sin precedente en este repo). En vez de eso, reabre LUKS, monta el
  `@` VIEJO (que sigue intacto en ese punto del proceso) y hace `arch-chroot` a él — ese `@` viejo ya tiene
  pacman, la keyring, y NetworkManager con los perfiles de red ya guardados, porque es literalmente el
  sistema que el usuario ya estaba usando.
- **Resumibilidad**: cada etapa es idempotente. Cada función `dc_*` revisa el marcador de estado antes de
  actuar; si su etapa ya está marcada completa, la salta por completo (mismo patrón que los `.done` de
  Phase 2). Si un reinicio corta a mitad de una etapa, esa etapa se reintenta DESDE CERO — nunca continúa a
  medias, nunca deja recursos huérfanos a medio crear.
- **Alcance de esta ronda**: esta ronda construye el mecanismo completo con tests de fixture (mismo rigor
  que Fase 0) — NO incluye el boot real de verificación en una VM UEFI+LUKS. Ese boot real queda como un
  paso aparte, con el usuario presente, después de que el código esté escrito y revisado. Fase 1 no se da
  por 100% cerrada (en el sentido del plan original) hasta ese boot, pero eso no bloquea escribir/revisar el
  código ahora.

## Arquitectura

### Flujo de un deep-clean armado (3 tramos)

**Tramo 1 — desde el escritorio, antes de rebootear** (la función `dc_arm_rescue`, invocada eventualmente
por el trigger de Fase 3 — en Fase 1 solo se construye la función, no el trigger):
1. Escribe el marcador de estado en el ESP con valor `staged` (ver "Máquina de estados" abajo).
2. Genera/actualiza la entrada de GRUB de rescate (`grub-mkconfig`, que invoca el nuevo
   `/etc/grub.d/41_archfrican_deepclean` — ver "Entrada de GRUB" abajo). La entrada solo se emite si el
   marcador `staged` existe; en cualquier otro momento `grub-mkconfig` no produce esa entrada, así que un
   usuario normal jamás la ve en su menú de arranque día a día.
3. Asegura `GRUB_DEFAULT=saved` en `/etc/default/grub` (reusa `set_grub_key` de `lib/grub.sh`, que ya existe
   — no hace falta código nuevo para editar ese archivo).
4. `grub-set-default archfrican-deepclean-rescue` (el `--id` estable de la entrada nueva) — persistente, NO
   `grub-reboot` de una sola vez. Si algo se corta a mitad de camino, el siguiente boot vuelve a caer en el
   entorno de rescate automáticamente, en vez de arrancar en silencio a un sistema a medio borrar.

**Tramo 2 — el reboot entra al initramfs de rescate** (hook de mkinitcpio nuevo,
`templates/initcpio/hooks/archfrican_deepclean`):
1. Reabre LUKS: `cryptsetup open <partición-raíz> root -` (mismo nombre de contenedor `root` que ya usa
   `lib/base-install.sh`), pidiendo la passphrase interactivamente — nunca se persiste en ningún lado.
2. Monta el `@` viejo (top-level, sin subvolumen específico) en un mountpoint de trabajo — usa
   `DC_ROOT_MNT` (ya definida en Fase 0 como `/mnt/deepclean`) montado sin `subvol=`, para poder ver TODOS
   los subvolúmenes del filesystem (necesario para `dc_wipe_subvolumes`/`dc_atomic_swap` más adelante).
3. Monta el subvolumen `@` viejo específicamente (con `subvol=@`) en un SEGUNDO mountpoint nuevo,
   `DC_OLD_MNT` (nueva variable, p.ej. `/mnt/deepclean-old`) — este es el que tiene un `/` completo y
   utilizable (pacman/systemd/NetworkManager), a diferencia del mount top-level del paso 2, que solo sirve
   para ver y manipular subvolúmenes como unidades. Hace `arch-chroot "$DC_OLD_MNT"` a él.
4. Dentro de ese chroot, ejecuta el script de continuación (Tramo 3).

El hook necesita empaquetar en el initramfs (vía su `install`-script,
`templates/initcpio/install/archfrican_deepclean`): `arch-chroot` (de `arch-install-scripts`) y sus
dependencias — `cryptsetup`/`btrfs` ya los trae el `encrypt`/`block` hook estándar de mkinitcpio, no hace
falta duplicarlos.

**Tramo 3 — dentro del chroot al `@` viejo (`DC_OLD_MNT`):**
1. Levanta red: `systemctl start NetworkManager` + espera a `nm-online -t 30` (reusa los perfiles de
   conexión ya guardados en `/etc/NetworkManager/system-connections/` del sistema viejo — cero
   configuración nueva).
2. Corre `run_deep_clean` desde el clone del repo que ya vive en `/home` (`clone_dest()` de `lib/env.sh`,
   sin tocar — `/home` nunca se toca en ningún punto de este proceso).
3. `run_deep_clean` (ya existe desde Fase 0, se extiende en Fase 1 — ver "Componentes nuevos y
   modificados") revisa el marcador de estado antes de cada etapa y la salta si ya está completa. Al llegar
   a `done`, llama a `dc_disarm_rescue` (restaura el default de GRUB anterior, borra el marcador) y reinicia
   a la instalación nueva.

**Nota sobre chroots anidados**: hay DOS chroots distintos en todo este flujo, que no deben confundirse.
El del Tramo 2 (a `DC_OLD_MNT`, el `@` viejo) es de ORQUESTACIÓN — le da a `run_deep_clean` acceso a
pacman/red/herramientas ya instaladas para poder construir el sistema nuevo. El de `dc_chroot_config_new`
(dentro de `@.new`, ver más abajo) es el chroot de CONFIGURACIÓN DEL SISTEMA NUEVO — corre DESDE DENTRO del
chroot de orquestación (un `arch-chroot` anidado dentro de otro; esto funciona sin problema, no requiere
nada especial). El primero envuelve todo el proceso; el segundo es un paso puntual dentro de
`dc_chroot_config_new`.

### `ARCHFRICAN_DEEPCLEAN_VERIFY_ONLY=1`

Reusa la infraestructura dry-run que YA existe desde Fase 0, sin código nuevo de gating: cuando está seteada,
fuerza `DC_GO` a quedarse en `0` sin importar el valor de `ARCHFRICAN_DEEPCLEAN_ARMED`. El initramfs de
rescate arranca de verdad — abre LUKS de verdad, monta de verdad, hace el chroot de verdad, levanta red de
verdad — pero cada `dc_run`/`dc_run_pipe` sigue solo imprimiendo, nunca ejecutando. Al terminar (llega a un
punto de "todo validado"), desarma la entrada y reinicia normal, sin haber tocado ni un subvolumen. Es la
forma más barata de probar que el mecanismo arranca en hardware real antes de arriesgar nada — y es
exactamente el boot que se hará como paso aparte tras esta ronda.

### Máquina de estados

Archivo plano en el ESP: `/boot/archfrican-deepclean/state` (una palabra, sin salto de línea final
obligatorio). Valores válidos, en orden: `staged` → `wiping` → `subvols-recreados` → `pacstrapped` →
`chroot-configurado` → `resume-inyectado` → `done`. Ausencia del archivo == no hay deep-clean en curso (el
hook de rescate ni siquiera debería poder arrancar sin él, ya que la entrada de GRUB solo existe cuando el
archivo existe).

Funciones nuevas en `lib/deep-clean.sh`:
- `dc_state_read()` — imprime el valor actual, o cadena vacía si el archivo no existe.
- `dc_state_write(valor)` — escribe atómicamente (escribe a un temporal en el mismo filesystem + `mv`, nunca
  edita in-place) — pasa por `dc_run`, respeta el gate dry-run igual que todo lo demás.
- `dc_state_at_or_past(etapa)` — helper de comparación de orden (`staged < wiping < ... < done`), usado por
  cada función `dc_*` para decidir si saltarse su propio trabajo.

Cada función de trabajo (`dc_wipe_subvolumes`, `dc_pacstrap_new`, `dc_chroot_config_new`, `dc_atomic_swap`,
etc.) sigue el patrón: `dc_state_at_or_past "<mi-etapa-o-posterior>" && return 0` al inicio; al terminar su
trabajo real, `dc_state_write "<mi-etapa>"`. Esto es lo que hace la "idempotencia por etapa" que decidimos
con el usuario — nunca continúa a medias, siempre reintenta la etapa completa desde el principio si se cortó
ahí.

**Guardia de reintentos**: `ARCHFRICAN_DEEPCLEAN_MAX_BOOTS` (default `3`, ya nombrada en el plan original).
Un contador adicional en el mismo directorio del ESP (`/boot/archfrican-deepclean/boot-count`) se incrementa
cada vez que el hook arranca; si supera el máximo sin llegar a `done`, el hook cae a un prompt de consola
manual (imprime el estado actual + instrucciones para `docs/RECOVERY.md`) en vez de loopear para siempre.

### Entrada de GRUB (condicional)

Nuevo `/etc/grub.d/41_archfrican_deepclean` (el primer script custom de `/etc/grub.d/` en este repo — no hay
precedente que reusar, pero sigue la forma estándar de cualquier script de esa carpeta: un script ejecutable
que `grub-mkconfig` invoca y cuya salida a stdout se concatena dentro de `grub.cfg`). Su lógica:

```bash
#!/bin/sh
# Emite el menuentry de rescate SOLO si hay un deep-clean en curso (marcador presente).
[ -f /boot/archfrican-deepclean/state ] || exit 0
cat <<EOF
menuentry 'Archfrican — Rescate (limpieza profunda)' --id archfrican-deepclean-rescue {
    <carga el kernel linux-lts + el initramfs-archfrican-deepclean.img ya construido>
}
EOF
```

(El bloque exacto de `linux`/`initrd` se resuelve contra los mismos UUID/rootflags que ya usa
`lib/base-install.sh`'s `_chroot_script` para el `GRUB_CMDLINE_LINUX` normal — reutilizar esa lógica, no
inventar una nueva.)

`dc_arm_rescue`/`dc_disarm_rescue` en `lib/deep-clean.sh` son las funciones que escriben/borran el marcador,
corren `grub-mkconfig`, y llaman `grub-set-default`/restauran el default anterior — todo detrás de
`dc_run`/`dc_run_pipe` como el resto del archivo.

## Componentes nuevos y modificados

**Nuevos:**
- `templates/initcpio/hooks/archfrican_deepclean` — hook runtime (Tramo 2 de arriba).
- `templates/initcpio/install/archfrican_deepclean` — install-script (empaqueta `arch-chroot` + deps).
- `templates/mkinitcpio-deepclean.conf` — preset mínimo: `HOOKS=(base udev autodetect modconf block encrypt
  filesystems archfrican_deepclean)` (sin `fsck`/hooks de escritorio normales — este initramfs nunca hace un
  boot de escritorio completo).
- `/etc/grub.d/41_archfrican_deepclean` (vía chezmoi, ruta exacta a definir en el plan de implementación).

**Modificados:**
- `lib/deep-clean.sh`: `dc_state_read`/`dc_state_write`/`dc_state_at_or_past`, `dc_arm_rescue`/
  `dc_disarm_rescue`, implementación REAL de `dc_detect_managed_layout` (parsear `btrfs subvolume list` de
  verdad, no solo el placeholder de Fase 0) y de `dc_chroot_config_new` (script real de chroot, espejando
  `_chroot_script` de `lib/base-install.sh` — locale/hostname/usuario/mkinitcpio/GRUB del sistema NUEVO
  dentro de `@.new`), guardia de reintentos (`ARCHFRICAN_DEEPCLEAN_MAX_BOOTS`).
- `lib/base-install.sh`: extraer `base_create_subvols()` del loop dentro de `base_format_mount()` para que
  `dc_wipe_subvolumes`/`dc_atomic_swap` puedan reusar la misma lógica de creación de subvolúmenes en vez de
  duplicarla.

## Testing

Mismo patrón de fixture que Fase 0 (`tests/unit/deep-clean.sh` extendido con casos para
`dc_state_read`/`dc_state_write`/`dc_state_at_or_past` y para que cada función de trabajo respete el
salteo-por-etapa-completa). Para la generación condicional de la entrada de GRUB: mismo patrón que la CI
`grub-helper` (stub del writer privilegiado, `mktemp` como fixture de `/boot/archfrican-deepclean/state` y de
`grub.cfg`, verificando que el menuentry aparece solo cuando el marcador existe y no aparece cuando no
existe).

**Explícitamente fuera de esta ronda**: cualquier test que requiera un boot real (VM o hardware) — eso es un
paso aparte, con el usuario presente, después de que este código esté escrito y revisado. La matriz
adversarial de corte de luz en cada etapa (Fase 4 del plan original) tampoco es parte de esta ronda.

## Riesgos conocidos (heredados del plan original, no resueltos aquí)

- La ventana de corte de luz durante el intercambio atómico de subvolúmenes y la finalización de GRUB sigue
  sin poder reducirse a cero — mitigada por la máquina de estados idempotente, pero no eliminada. Esto se
  documenta honestamente en fases posteriores (Fase 4/docs), no se resuelve en Fase 1.
- El caso límite de cambio de nombre de usuario durante el wizard (Fase 2) es ortogonal a este documento.
