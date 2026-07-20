# Fix `archfrican-resume.service`'s broken fail-closed retry loop

## Contexto

`archfrican-resume.service` runs the headless first-boot install (Stage 2). It carries a temporary
`NOPASSWD: ALL` sudoers drop-in (`/etc/sudoers.d/99-archfrican-resume`) so the non-interactive resume
can use sudo without a TTY. `lib/resume-guard.sh` (its `ExecStartPre`) bounds that elevated window:
each boot bumps a counter in `/var/lib/archfrican/resume-attempts`; after
`ARCHFRICAN_RESUME_MAX_BOOTS` (default 5) failed boots it's supposed to remove the sudoers drop-in
and `sudo systemctl disable` the unit — "fail closed," so passwordless root can never linger forever
on a permanently-broken install.

**Confirmed live on the daily-driver machine** (full `journalctl -u archfrican-resume.service`
history, not guessed): the original install on 2026-06-29 completed successfully. Something
interrupted it before `ExecStartPost` could run (the log shows a `Failed with result 'signal'` the
next day, consistent with a mid-build reboot). From 2026-06-30 onward, **every single boot for 3
weeks** — through today, 2026-07-20 — re-triggered the unit, immediately hit the "6 failed boots"
ceiling, printed "disabling the unit (fail-closed)," and exited 1. The unit is still enabled today,
which is proof the disable never actually took effect: **the fail-closed branch's own
`sudo systemctl disable` call depends on the same NOPASSWD grant that's already broken by the time
that branch runs** — a chicken-and-egg failure. Once the sudoers drop-in is gone (or was never
valid for that invocation), every subsequent boot's guard can neither persist the counter (it's
written via `sudo tee`) nor actually disable the unit — it just repeats forever, printing a success
message that isn't true.

This isn't cosmetic: on 2026-07-20, this zombie retry loop ran concurrently with a manual
`archfrican-update --converge` invocation, and the resulting resource contention triggered two real
system reboots within a 20-minute window (confirmed via `systemd[1]: Starting Archfrican first-boot
install...` boot-time log entries, not just a user-session crash).

## Alcance

**Sí cubre:**
- Move the resume-guard's attempt counter and a new "stop retrying" marker to user-owned state
  (`${XDG_STATE_HOME:-$HOME/.local/state}/archfrican/` — the same directory `lib/phase2.sh`/
  `lib/converge.sh` already use for per-module `.done` stamps), so writing them never needs sudo.
- Add `ConditionPathExists=!<marker>` to `templates/archfrican-resume.service` so **systemd itself**
  refuses to start the unit once the marker exists — no external command, no sudo, no chicken-and-egg.
  The same marker is touched on BOTH the success path (`ExecStartPost`) and the give-up path
  (`resume-guard.sh`'s fail-closed branch), unifying "never run again" into one mechanism.
- A new migration (`migrations/0003-fix-resume-failclosed-loop.sh`, following the exact pattern of
  `migrations/0001-resume-sudoers-rename.sh` and `0002-greetd-to-sddm.sh`) that remediates
  **already-deployed, already-stuck machines** — it runs from `archfrican-update`'s interactive
  context (real sudo, real password prompt), so it can actually disable the old unit and clean up
  the stale sudoers drop-in and counter, then write the new marker so the fix holds even if
  something re-enables the unit later.
- A unit test for the new counter/marker logic in `lib/resume-guard.sh`, following the exact
  stub pattern already used in `tests/unit/fw_allow.sh` (`sudo(){ "$@"; }`, fixture directories via
  `mktemp`, no root/no real systemd needed, runs in CI).

**Explícitamente fuera de alcance** (decisión tomada durante el brainstorming — el usuario eligió
enfocar esta ronda en un solo problema):
- **No se toca la detección "sin terminal interactiva, no seguir a medias"** en `archfrican-update`/
  `install.sh` en general — eso quedó identificado como un problema relacionado pero separado, para
  una ronda futura.
- **No se agrega protección contra out-of-memory** (p.ej. `OOMScoreAdjust` en unidades del escritorio,
  o un pre-chequeo de memoria antes de operaciones pesadas) — también identificado, también diferido.
- **No se cambia `ARCHFRICAN_RESUME_MAX_BOOTS` ni la lógica de conteo en sí** (sigue siendo 5 por
  defecto, sigue incrementando igual) — el bug es específicamente que el mecanismo de "dejar de
  reintentar" no se puede ejecutar, no el umbral en sí.
- **El sudoers drop-in (`/etc/sudoers.d/99-archfrican-resume`) sigue intentándose remover con sudo
  best-effort** (no es load-bearing para detener los reintentos, pero sigue siendo deseable
  limpiarlo cuando sudo sí funciona) — no se rediseña ese mecanismo, solo deja de ser el punto único
  de fallo.

## Arquitectura

### `lib/resume-guard.sh`

Estado movido de `/var/lib/archfrican` (root, `install -d -m 0755` + `sudo tee`) a
`${XDG_STATE_HOME:-$HOME/.local/state}/archfrican/` (mismo patrón ya usado como `PHASE2_STATE`/
`ARCHFRICAN_PHASE2_STATE` en `lib/phase2.sh`/`lib/converge.sh` — el usuario ya es dueño de ese
directorio, `mkdir -p` sin sudo alcanza):

```bash
state="${XDG_STATE_HOME:-$HOME/.local/state}/archfrican"
mkdir -p "$state"
counter="$state/resume-attempts"
stopped="$state/resume-stopped"
```

El conteo sigue igual (`cat`/incrementar/reescribir), pero ahora vía `printf ... > "$counter"`
directo (no `sudo tee`) — nunca puede fallar por falta de privilegio.

Al superar `MAX`, el orden importa: primero la acción que SIEMPRE funciona, después la limpieza
best-effort:

```bash
if [ "$n" -gt "$MAX" ]; then
  echo "archfrican-resume: giving up after $((n - 1)) failed boots — stopping future retries" \
       "(fail-closed). See: journalctl -u archfrican-resume -b" >&2
  touch "$stopped"                              # load-bearing: systemd's own Condition reads this
  sudo rm -f "$dropin" 2>/dev/null || true       # best-effort cleanup, no longer required for correctness
  sudo systemctl disable archfrican-resume.service 2>/dev/null || true
  exit 1
fi
```

### `templates/archfrican-resume.service`

Una línea nueva en `[Unit]`:

```ini
ConditionPathExists=!/home/@USER@/.local/state/archfrican/resume-stopped
```

Esto reemplaza la dependencia de `systemctl disable` como el mecanismo real de "no arrancar más" —
systemd evalúa esta condición ANTES de correr `ExecStartPre`, con su propio privilegio de PID 1, sin
necesitar sudo de ningún tipo. `ExecStartPost` (camino exitoso) toca el mismo marcador:

```ini
ExecStartPost=/usr/bin/touch /home/@USER@/.local/state/archfrican/resume-stopped
ExecStartPost=/usr/bin/sudo /usr/bin/systemctl disable archfrican-resume.service
ExecStartPost=/usr/bin/sudo /usr/bin/rm -f /etc/sudoers.d/99-archfrican-resume
```

(el `touch` va primero y sin `sudo` — corre como `User=@USER@`, igual que el resto del unit — las dos
líneas de `sudo` que siguen quedan como limpieza best-effort, ya no son las que impiden reintentos
futuros).

**Nota de consistencia:** `ConditionPathExists=` en un unit de systemd no expande variables de
shell — no puede leer `$XDG_STATE_HOME`. La ruta hardcodeada `/home/@USER@/.local/state/...` asume
el default (`XDG_STATE_HOME` sin setear), que es exactamente lo que ve `resume-guard.sh` dentro de
este mismo unit (el `[Service]` no define `Environment=XDG_STATE_HOME=...`), así que ambos lados
resuelven al mismo path siempre. Si el usuario tiene `XDG_STATE_HOME` exportado en su propio shell
interactivo eso no importa acá — este unit corre con su propio entorno mínimo, no hereda el shell
del usuario.

### `migrations/0003-fix-resume-failclosed-loop.sh` (nueva)

Mismo estilo que `0001`/`0002` — idempotente, no-op en instalaciones nuevas o ya sanas:

```bash
#!/usr/bin/env bash
# 0003 — stop an archfrican-resume.service stuck retrying every boot forever.
# The fail-closed branch in lib/resume-guard.sh used to depend on sudo systemctl disable
# succeeding -- but if the NOPASSWD grant is already gone by the time that branch runs, that
# call silently fails too, and the unit keeps retrying (and failing) on every single boot.
# This migration runs from an interactive archfrican-update context (real sudo), so it can
# actually break the loop: disable the unit if enabled, clean up the stale grant/counter, and
# write the new user-owned marker so a future re-enable still can't restart it.
set -euo pipefail
state="${XDG_STATE_HOME:-$HOME/.local/state}/archfrican"
mkdir -p "$state"

if systemctl is-enabled --quiet archfrican-resume.service 2>/dev/null; then
  sudo systemctl disable archfrican-resume.service
  printf '  \e[32m✓\e[0m disabled archfrican-resume.service (was stuck retrying every boot)\n'
else
  printf '  \e[32m✓\e[0m archfrican-resume.service already disabled (nothing to do)\n'
fi

if [ -e /etc/sudoers.d/99-archfrican-resume ]; then
  sudo rm -f /etc/sudoers.d/99-archfrican-resume
  printf '  \e[32m✓\e[0m removed stale resume sudoers drop-in\n'
fi

if [ -e /var/lib/archfrican/resume-attempts ]; then
  sudo rm -f /var/lib/archfrican/resume-attempts
  printf '  \e[32m✓\e[0m removed stale root-owned attempt counter\n'
fi

touch "$state/resume-stopped"
printf '  \e[32m✓\e[0m wrote %s (blocks any future re-enable)\n' "$state/resume-stopped"
```

## Manejo de errores

- Si `archfrican-resume.service` ya no existe como unidad (una instalación nueva post-fix nunca la
  deja atascada), `systemctl is-enabled` simplemente reporta "no encontrado" y la migración toma la
  rama "nada que hacer" — no falla.
- El `touch "$stopped"` en `resume-guard.sh` y en `ExecStartPost` nunca puede fallar por falta de
  privilegio (corre como el usuario dueño de su propio `$HOME`); el único fallo posible sería un
  `$HOME` sin espacio en disco o similar, fuera del alcance de este fix.
- La migración es puramente aditiva/idempotente: correrla dos veces no rompe nada (cada rama ya
  chequea el estado actual antes de actuar), igual que `0001`/`0002`.

## Testing / validación

- `bash -n` sobre `lib/resume-guard.sh` y `migrations/0003-fix-resume-failclosed-loop.sh`.
- Nuevo test unitario (`tests/unit/resume-guard.sh`, mismo patrón que `tests/unit/fw_allow.sh`):
  fixture con `XDG_STATE_HOME` apuntando a un `mktemp -d`, stub de `sudo(){ "$@"; }`, confirma que:
  1. El contador se escribe sin sudo.
  2. Al superar `MAX`, se crea `$state/resume-stopped` ANTES de cualquier intento de limpieza sudo
     (para que quede claro que no depende de que esos comandos tengan éxito).
  3. Una segunda invocación con el marcador ya presente no vuelve a incrementar el contador
     innecesariamente (aunque esto ya lo cubre `ConditionPathExists` a nivel systemd — el test es
     sobre el script en sí, no sobre systemd).
- Verificación en vivo en esta máquina (ya está en el estado exacto que este fix apunta a arreglar):
  correr la migración real, confirmar `systemctl is-enabled archfrican-resume.service` reporta
  `disabled`, y confirmar que el próximo boot no vuelve a intentarlo (`journalctl -u
  archfrican-resume.service -b` debe quedar vacío en el boot siguiente).
