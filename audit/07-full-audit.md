# Phase 7 — Full-stack audit (estabilidad, rendimiento, escalabilidad, testing, seguridad, features)

**Por qué existe:** las rondas anteriores (`00`–`06`) se congelaron en el core del instalador y en el
trabajo de features posterior hasta ~10 de julio. Desde entonces el proyecto sumó una cantidad
significativa de trabajo nuevo (rediseño de waybar, wallpaper bundling, sesión opcional de Plasma, menú
de energía/sistema, agente SSH por defecto, fix del portal de captura de pantalla para niri, fix de la
carrera de doble-lanzamiento de swaync, entre otros) que ninguna ronda anterior examinó. Esta auditoría
cubre esa superficie completa, más una revisión general de seis dimensiones sobre todo el repo.

**Método:** 6 buscadores en paralelo (uno por dimensión: estabilidad, rendimiento, escalabilidad/
refactoring, testing/CI, seguridad, nuevas funcionalidades), cada uno con contexto explícito de qué ya
está arreglado (para no re-reportar bugs ya cerrados en rondas/commits previos). Cada dimensión pasó por
un triage independiente que releyó el código real citado antes de confirmar cada hallazgo. **37
candidatos → 37 sobrevivieron el triage, 0 descartados** (todos los candidatos ya llegaban verificados
contra archivos reales, varios reproducidos en vivo — el `eval` de multiboot, los timeouts de systemd,
los tiempos de arranque de shell). Todo hallazgo cita `file:line`.

---

## Resumen ejecutivo

- **Quick win crítico #1 (seguridad):** `lib/multiboot.sh:73` ejecuta `eval "$line"` sobre datos de
  `lsblk` sin validar, dando inyección de comandos en contexto root disparable por una etiqueta de USB
  maliciosa. Reproducido en vivo. Corrección pequeña, impacto alto. **Empezar por acá.**
- **Quick win crítico #2 (estabilidad):** el backup diario (`archfrican-backup`) corre como
  `Type=oneshot` sin `TimeoutStartSec`, heredando el default de 90s (confirmado en vivo) — cualquier
  `restic backup` largo es SIGKILLeado en silencio sin notificar. Una línea de fix.
- **Quick wins de rendimiento agrupables:** `notify-send` sin `-t` que se auto-mata a los 90s y ensucia
  el health status (AMBER recurrente), inicializaciones de shell sin diferir que rompen 1.6x el
  presupuesto declarado de 50ms del propio `dot_zshrc`, y polls de waybar (health cada 30min con caché
  ya vencida, connectivity cada 10s indefinido) — todos son fixes pequeños de alto/medio impacto.
- **Deuda estructural #1:** duplicación masiva por copiar-pegar — 57 entradas de menú byte-a-byte entre
  `archfrican-actions` y `actions.toml.tmpl` (ya causó un doble-commit real), `have()/note()` clonados en
  ~26 scripts, y 5 listas paralelas de módulos que deben concordar a mano sin guarda de CI.
- **Deuda estructural #2:** los motores núcleo (`lib/converge.sh` hash/drift, `lib/health.sh` ~19
  checks, `archfrican-defaults` fuente única de 11 providers) tienen **cero** cobertura de tests, y el
  workflow de ISO publica la nightly sin ninguna validación estructural del artefacto.

---

## 1. Estabilidad y confiabilidad

### 1.1 [CRÍTICO] Backup diario sin `TimeoutStartSec` → SIGKILL silencioso
**Archivos:** `home/dot_local/bin/executable_archfrican-backup:50-56` (unit escrita por la acción
`schedule`), `:41` (`restic backup "$HOME"`)

La `.service` es `Type=oneshot` corriendo `archfrican-backup now`; ni la `.service` ni la `.timer` fijan
`TimeoutStartSec`, así que heredan `DefaultTimeoutStartUSec` = **1min30s** (confirmado en vivo vía
`systemctl --user show`). Cualquier backup que exceda ~90s (primer backup, repo grande, remoto rclone
lento) es matado por systemd desde fuera del script, por lo que ni la rama de éxito ni la de fallo
(`note(...)`, `:41-45`) llega a ejecutarse: backup truncado, silencioso y sin notificar.

**Acción:** añadir `TimeoutStartSec=infinity` (o un valor amplio, p.ej. `2h`) a la unit generada en
`:50-56`, alineándolo con el patrón ya usado en `templates/archfrican-resume.service:31`.

### 1.2 [IMPORTANTE] `archfrican-update` do_notify sin `-t` → auto-fallo y AMBER recurrente
**Archivos:** `bin/archfrican-update:190-193` (do_notify), `modules/70-hygiene.sh:87-93` (unit),
`lib/health.sh:15-20` (check_failed_units)

`do_notify()` llama `notify-send -A ... -A ...` sin `-t/--expire-time`; `-A` implica `--wait`, así que el
proceso bloquea hasta que el usuario accione la notificación. La unit `archfrican-update-check.service`
es `Type=oneshot` sin override de timeout (90s en vivo), así que si el usuario no actúa en 90s systemd
mata el proceso y marca la unit como failed, que `check_failed_units` (`systemctl --user --failed`)
luego expone como finding AMBER 'services' recurrente en `archfrican-doctor`.

**Acción:** acotar la notificación con `-t 25000` como ya hace
`executable_archfrican-welcome-notify:13`.

### 1.3 [IMPORTANTE] Fetches de red sin timeout en el path de instalación obligatorio
**Archivos:** `modules/00-base.sh:9` (curl sin `--max-time`), `modules/30-dev.sh:9-10` (rustup/fnm),
`lib/common.sh:213` (aur_install `paru -S`), `modules/40-theming.sh:9` (aur_install_file, no-opt-in),
`modules/35-apps.sh:15,27` (flatpak remote-add/install), `templates/archfrican-resume.service:31`
(`TimeoutStartSec=infinity`)

Estas llamadas de red están sólo guardadas por `best_effort/attempt`, que —según el propio doc-comment
de `lib/common.sh`— sólo capturan exit no-cero, nunca un cuelgue. Como `archfrican-resume.service:31`
fija `TimeoutStartSec=infinity` a propósito, una conexión estancada cuelga el resume de primer arranque
**indefinidamente**, con el grant temporal NOPASSWD sudoers vivo durante todo ese tiempo. El propio
comentario de `modules/40-theming.sh:14-16` ya diagnostica y arregla esta clase de bug para gsettings
con `timeout 5`, pero no se extendió.

**Acción:** envolver cada llamada de red del path phase2 con `timeout N` (o `curl --max-time`),
replicando el patrón de `40-theming.sh:14-16`.

### 1.4 [IMPORTANTE] `module_inputs` de 40-theming omite `lib/grub.sh` → blind spot de drift
**Archivos:** `lib/converge.sh:31` (case 40-theming), `modules/40-theming.sh:4` (source lib/grub.sh),
`:63-64` (set_grub_key)

El case de `40-theming` lista sólo `packages/theming.txt packages/aur.txt bin/theme-switch themes
templates`, pero el módulo hace `source lib/grub.sh` y llama `set_grub_key`. Como `lib/grub.sh` no está
en los inputs hasheados, un cambio de comportamiento en su lógica de render no cambia el hash de
40-theming, así que `run_module` seguiría reportando 'unchanged' y saltándose la re-convergencia (tanto
en re-run como en `--converge`). Los módulos hermanos `10-gpu` (`:23`) y `55-multiboot` (`:33`) sí lo
listan, confirmando el descuido.

**Acción:** añadir `lib/grub.sh` a la lista de inputs de 40-theming en `lib/converge.sh:31`.

### 1.5 [MENOR] Sin exclusión mutua (flock) en el pipeline git/pacman/converge
**Archivos:** `bin/archfrican-update:136` (`git reset --hard FETCH_HEAD`), `:236` (`sudo pacman -Syu`),
`:194-198` (do_notify lanza ghostty)

Cero coincidencias de `flock` en todo el repo y sin lockfile/pidfile alternativo. Dos invocaciones
concurrentes (un `--run` manual más el `--run` disparado por la notificación) pueden competir sobre el
clone git compartido o escrituras solapadas de converge/DB. El db-lock de pacman sólo cubre la
transacción de paquetes, no la mutación git ni las escrituras de config alrededor.

**Acción:** envolver el pipeline con `flock -n` sobre un lockfile dedicado; salir limpio si ya hay una
instancia corriendo.

---

## 2. Rendimiento

### 2.1 [IMPORTANTE] waybar `custom/health` corre la suite completa cada 30min sin caché útil
**Archivos:** `home/dot_config/waybar/config.jsonc:84` (`interval: 1800`, `exec: archfrican-doctor
--json`), `bin/archfrican-doctor:36` (`HEALTH_TTL=900`), `:37-40`, `:31-34`, `lib/health.sh:57-64`
(run_all_checks)

El TTL de caché (900s) es la mitad del intervalo de poll (1800s), así que en el caso monitor-único la
caché escrita en tick T ya está stale en T+1800 — el comentario `:31-34` confirma que la caché es sólo
para de-dup entre monitores, no para reducir el coste por tick. `run_all_checks()` invoca 22 funciones
`check_*` cada vez, dos de ellas de red real: `check_updates` (`checkupdates`) y `check_firmware`
(`fwupdmgr get-updates`). Ambos binarios (pacman-contrib, fwupd) están en `packages/base.txt`, así que
corre por defecto en todo desktop.

**Acción:** separar los checks de red del poll de waybar (p.ej. cachearlos con un TTL mayor que el
intervalo, o moverlos a un timer systemd de baja frecuencia), dejando el tick de waybar leyendo sólo
estado barato.

### 2.2 [IMPORTANTE] waybar `custom/connectivity` hace ping a internet cada 10s para siempre
**Archivos:** `home/dot_config/waybar/config.jsonc` (`custom/connectivity interval: 10`),
`home/dot_local/bin/executable_archfrican-net-status:8` (`ping -c 3 -w 3 1.1.1.1`)

Hasta 3 round-trips ICMP y hasta 3s de bloqueo cada 10s, indefinidamente (~8640 ticks/día), lo que puede
vencer el power-save de WiFi/módem en portátiles.

**Acción:** subir el intervalo y/o preferir una comprobación de estado de enlace event-driven
(NetworkManager state) antes de recurrir a un ping ocasional.

### 2.3 [MENOR] waybar `custom/privacy` forkea pw-dump + jq cada 3s
**Archivos:** `home/dot_config/waybar/config.jsonc` (`custom/privacy interval: 3`),
`home/dot_local/bin/executable_archfrican-privacy-indicator:11-17`, `:4` (comentario del tradeoff)

Forkea `pw-dump | jq` (dos forks) en cada tick, use o no el mic/cámara. El comentario `:4` declara que
es un tradeoff deliberado de "sin daemon extra"; el rework a un suscriptor event-driven `pw-mon` es
legítimo pero no trivial.

**Acción:** opcional — migrar a un listener `pw-mon` de larga vida que sólo re-evalúe en eventos; si no,
subir el intervalo.

### 2.4 [IMPORTANTE] Inicializaciones de shell no diferidas rompen el presupuesto de <50ms
**Archivos:** `home/dot_zshrc:1` (target "<50ms"), `:15-18` (zinit diferido con `wait lucid`), `:30-36`
(5 inits síncronos)

Las líneas 30-36 corren 5 `command -v X && eval "$(X ...)"` síncronos (zoxide, fnm, direnv, atuin,
starship) sin deferral, a diferencia de los plugins de zinit. Medido en esta máquina: zoxide ~7ms, fnm
~39ms, direnv ~14ms, starship ~19ms = **~79ms** combinados (~1.6x el presupuesto de 50ms), antes de
contar atuin.

**Acción:** diferir estos inits con el mismo mecanismo turbo (`wait lucid`) ya usado para zinit en
`:15-18`, o precomputar/cachear su salida.

### 2.5 [MENOR] `modules/10-gpu.sh` hace dos transacciones pacman separadas en NVIDIA híbrido
**Archivos:** `modules/10-gpu.sh:35-38` (nouveau), `:42-44` (propietario), `lib/common.sh:195-203`
(cada `pac_install` es su propia transacción)

Coste one-time de instalación (no runtime), sólo afecta portátiles NVIDIA-híbridos.

**Acción:** acumular los paquetes en un array y hacer un único `pac_install` por rama.

### 2.6 [MENOR] `modules/35-apps.sh` instala el catálogo Flatpak app-por-app
**Archivos:** `modules/35-apps.sh:22-28` (loop con `flatpak info` + `flatpak install` por entrada),
`flatpak/apps.txt` (2 activas, ~9 comentadas)

Coste actual pequeño pero crece si se activan más apps.

**Acción:** pasar la lista entera a una sola invocación `flatpak install`.

---

## 3. Escalabilidad, arquitectura y refactoring

### 3.1 [IMPORTANTE] 57 entradas de menú duplicadas byte-a-byte entre dos archivos
**Archivos:** `home/dot_local/bin/executable_archfrican-actions:22-148` (fallback fuzzel),
`home/dot_config/elephant/menus/actions.toml.tmpl` (238 líneas, 57 `[[entries]]`), +
`executable_archfrican-layout` vs `menus/layout.toml` (7 entradas), submenú 'Pantallas' vs
`menus/pantallas.toml.tmpl`. Patrón alternativo ya establecido: `defaults-helpers.lua:3-4` y
`keys.lua:13-14` hacen `io.popen` a `archfrican-defaults __list` / `archfrican-keys __tsv`.

Las mismas 57 etiquetas españolas mapeadas a los mismos comandos, en dos sitios. Historia git confirma
el doble-commit (bfd6265 + a932304, ~10min de diferencia, mismas 5 entradas añadidas dos veces).

**Acción:** single-source las entradas (un generador o TSV consumido por ambos front-ends), replicando
el patrón `io.popen` de defaults-helpers/keys.

### 3.2 [IMPORTANTE] Cabecera de `20-niri-desktop.sh` es falsa — ~40% son servicios de los que Plasma depende
**Archivos:** `modules/20-niri-desktop.sh:2-3` (cabecera "niri lives ONLY in this module"), `:29-78`
(SDDM), `:80-83` (NetworkManager), `:85-91` (pipewire/wireplumber), `:180-188` (Bluetooth), `:190-200`
(power-profiles-daemon), `:202-204` (XDG dirs), `:206-211` (sensors-detect); `modules/25-plasma-desktop.sh:5`
("Never touches niri/waybar/...")

Plasma no habilita NetworkManager/Bluetooth/power-profiles por sí mismo, así que depende silenciosamente
de que 20-niri-desktop haya corrido antes.

**Acción:** extraer los servicios compartidos a un nuevo `modules/15-desktop-services.sh`, replicando
cómo 25-plasma/55-multiboot ya se separaron en módulos numerados propios.

### 3.3 [IMPORTANTE] Lista de módulos duplicada a mano en 5 sitios sin guarda de consistencia
**Archivos:** `lib/converge.sh:15` (ARCHFRICAN_MODULES, 13 nombres), `:19-38` (module_inputs case),
`lib/phase2.sh:24-30` (module_label), `:31-45` (module_desc), `:208-221` (run_module literales);
`.github/workflows/ci.yml` (sin referencia)

5 sitios independientes que deben concordar; grep confirma que nada (ni CI ni tests) verifica que las 4
listas + `modules/*.sh` en disco sigan sincronizadas. Hoy concuerdan, pero no hay guarda contra drift
futuro.

**Acción:** añadir un test/step de CI que verifique que los nombres en las 4 listas coinciden entre sí y
con `ls modules/*.sh`.

### 3.4 [IMPORTANTE] `have()/note()`/confirm-dialog copiados en ~26 scripts sin lib compartida
**Archivos:** 26 de 47 `executable_*` bajo `home/dot_local/bin` definen su propio `have()` idéntico; 25
su propio wrapper `note()` (4 variantes textuales); idiom 'Sí,.../Cancelar' inlineado en
`executable_archfrican-secureboot:16`, `archfrican-tpm-unlock:29`, `archfrican-rollback:20`,
`archfrican-plymouth:33`, `archfrican-actions:12`. Cero scripts sourcean un archivo compartido hoy.

**Acción:** crear un `home/dot_local/lib/archfrican-common.sh` (o similar) con `have`/`note`/
confirm-dialog y sourcearlo desde los scripts.

### 3.5 [IMPORTANTE] `archfrican-defaults` (fuente única de 11 providers `defaults-*.lua`) sin tests
**Archivos:** `home/dot_local/bin/executable_archfrican-defaults` (259 líneas, 0 tests), `:215-216`
(`__list`/`__apply`), `home/dot_config/elephant/lib/defaults-helpers.lua:3-4`,
`.github/workflows/ci.yml:~314-331` (unit-logic job)

CI ya corre 8 test files (detect-gpu, fw_allow, multiboot, disk, displays, manifest, deep-clean, fido2),
pero ninguno toca `archfrican-defaults`, del que dependen 11 providers vía shell-out.

**Acción:** añadir `tests/unit/defaults.sh` mockeando el shell-out, siguiendo el patrón `manifest.sh`, y
engancharlo al unit-logic job.

### 3.6 [MENOR] Handoff phase1↔phase2 usa paths de marker hardcodeados sin accessor compartido
**Archivos:** `lib/phase1.sh:31` (`.archfrican-answers` escrito), `lib/phase2.sh:150,153` (leído);
`lib/phase2.sh:144` (`.config/.archfrican-fido2` escrito), `modules/60-security.sh:174` (leído);
`.archfrican-theme`/`.archfrican-kbd` escritos dos veces (`phase1.sh:33-34`, `phase2.sh:194-195`);
`/var/lib/archfrican/firstboot-done` en `phase2.sh:280`

Sin constantes nombradas ni helpers writer/reader; conectados sólo por comentarios.

**Acción:** definir constantes/funciones accessor en un lib compartido y usarlas en todos los sitios de
escritura/lectura.

### 3.7 [MENOR] `modules/60-security.sh` mezcla hardening con hardware/power
**Archivos:** `modules/60-security.sh:116-123` (logind lid/suspend — power), `:137-151` (microcode +
regen GRUB — hardware/bootloader); el resto (`:12-53` firewall, `:75-105` sysctl, etc.) es hardening
genuino. Empatado con `20-niri-desktop.sh` como los dos módulos más grandes (199 vs 213 líneas).

**Acción:** mover las líneas de power/microcode a un módulo de hardware/servicios apropiado.

---

## 4. Testing y CI

### 4.1 [IMPORTANTE] `lib/converge.sh` (motor hash/drift) sin cobertura unit
**Archivos:** `lib/converge.sh:19-37` (module_inputs), `:44-58` (module_hash), `:63-69`
(drift_modules); único exerciser `tests/e2e/selftest.sh:177-208` (requiere sistema instalado, no corre
en CI)

Contiene branching real (case por módulo, hashing dir-vs-file con `LC_ALL=C sort`, comparación
stamp-vs-hash) no referenciado por ningún test en `tests/unit/`.

**Acción:** añadir `tests/unit/converge.sh` basado en fixtures, siguiendo el patrón
`manifest.sh`/`disk.sh`.

### 4.2 [IMPORTANTE] Sin test de regresión para 'spawn-at-startup compite con unit systemd --user'
**Archivos:** `modules/20-niri-desktop.sh:100,115` (resilient_enable_user waybar/swaync),
`home/dot_config/niri/config.kdl.tmpl:143-154` (spawn-at-startup, sin waybar/swaync);
`.github/workflows/ci.yml` (sin step)

Ambos fixes históricos se sostienen hoy, pero nada los bloquea.

**Acción:** step de CI que compare los nombres de programa de spawn-at-startup contra los service names
de `resilient_enable_user` y falle en solape.

### 4.3 [MENOR] Invariante 'D-Bus timeout-wrapped + swaync-client -sw' sólo en comentarios
**Archivos:** gsettings wrapped en `timeout 5` en `modules/40-theming.sh:17-22`,
`bin/theme-switch:146-152`, `executable_archfrican-a11y:6`; swaync-client con `-sw` en
`bin/theme-switch:228`, `executable_archfrican-actions:123-124`; invariante documentada sólo en
comentario `bin/theme-switch:223-227`

**Acción:** step grep de CI que verifique que todo call-site de gsettings/swaync-client lleve el
wrapper/flag.

### 4.4 [MENOR] `lib/health.sh` (~19 checks) y sus modos `--json`/`--fix` sin cobertura
**Archivos:** `lib/health.sh:31-40` (check_disk thresholds), `:167-175` (check_drift), `:184-197`
(check_niri_config), `:217-229` (check_theme_render); `bin/archfrican-doctor` (lógica de caché/
agregación ok/amber/red)

**Acción:** `tests/unit/health.sh` stubbeando df/journalctl/systemctl/snapper como funciones shell.

### 4.5 [MENOR] Fix de word-splitting del wallpaper picker sin test de regresión
**Archivos:** `home/dot_local/bin/executable_archfrican-wallpaper:19-27` (`while IFS= read -r f`),
`tests/unit/disk.sh` (patrón análogo pero para list_disks)

**Acción:** añadir `tests/unit/wallpaper.sh` con una aserción de nombres con espacios.

### 4.6 [MENOR] `tests/e2e/README.md` omite el subcomando 'update' que selftest.sh sí implementa
**Archivos:** `tests/e2e/selftest.sh:177-208` (assert_update, dispatch `update)`), `tests/e2e/README.md`
(grep 'update' = 0 matches)

Es el único sitio que ejercita `drift_modules` end-to-end y no está documentado.

**Acción:** documentar el subcomando `update` en la sección de subcomandos del README.

### 4.7 [IMPORTANTE] `iso.yml` construye y publica la nightly sin validación estructural del ISO
**Archivos:** `.github/workflows/iso.yml` (único post-build: 'Compute ISO filename' vía `ls`; luego
upload + `softprops/action-gh-release` force-update de 'nightly'), `build-iso.sh` (única "validación":
imprime un comando qemu sugerido, nunca ejecutado)

No existe check de unsquashfs/tamaño/existencia de archivos.

**Acción:** añadir un gate post-build (unsquashfs listing + verificación de tamaño mínimo + existencia
de kernel/initramfs) antes del upload y del force-update de la release.

---

## 5. Seguridad

### 5.1 [CRÍTICO] `eval` sobre campos de lsblk = inyección de comandos vía etiqueta de USB
**Archivos:** `lib/multiboot.sh:73` (`eval "$line"`), `:88` (`lsblk -Pno
NAME,PKNAME,FSTYPE,PARTTYPE,MOUNTPOINT`); alcanzado desde `lib/phase1.sh` (wizard), `lib/phase2.sh` (x2,
resume en root), `bin/archfrican-doctor:24`; `packages/niri-desktop.txt:43-45` (gvfs);
`tests/unit/multiboot.sh` (sólo testea `_af_esp_os`, nunca este path)

`eval "$line"` corre sobre cada línea **antes** de validar campos. `lsblk -P` sólo escapa comillas/
backslashes, no metacaracteres shell, así que un MOUNTPOINT con `$(cmd)` ejecuta como código.
**Reproducido en vivo:** `MOUNTPOINT="/run/media/user/$(touch /tmp/pwned_test)"` creó el archivo. El
MOUNTPOINT de un USB removible deriva del LABEL vía gvfs/udisks2, y un label FAT/NTFS es totalmente
controlable por el atacante. Primitiva de inyección en contexto root disparable por un USB automontado.

**Acción:** eliminar el `eval`; parsear `lsblk` en JSON (`lsblk -J`) o con `read` sobre delimitadores
controlados, sin evaluar datos externos como código. **Prioridad máxima.**

### 5.2 [IMPORTANTE] Chain `forward` de nftables con policy accept
**Archivos:** `modules/60-security.sh:38` (`chain forward { ... policy accept; }` sin reglas), `:27-37`
(input deny-by-default)

Asimetría real: input es deny-by-default con accepts explícitos, forward pasa cualquier cosa una vez el
forwarding esté activo (bridges de VM, Docker/podman, `net.ipv4.ip_forward=1`). No es explotable por sí
solo (requiere forwarding habilitado), pero es un gap de defensa en profundidad.

**Acción:** poner `policy drop` en la chain forward con accepts explícitos según necesidad, alineándolo
con el patrón de scoping estricto que usa `archfrican-continuity`.

### 5.3 [MENOR] Accepts baseline de mDNS/DHCP sin scoping por origen
**Archivos:** `modules/60-security.sh:34-36` (DHCPv4/v6/mDNS desde cualquier origen), contraste con
`home/dot_local/bin/executable_archfrican-continuity:11-20` (scope RFC1918 + link-local/ULA)

Threat model plausible (Wi-Fi público hostil expone avahi/cliente-DHCP). **Caveat:** scopear mDNS es
bajo-riesgo; scopear DHCP (67/68, 547/546) necesita testing porque durante DHCPDISCOVER/OFFER el cliente
aún no tiene IP y algunas redes usan relay.

**Acción:** scopear mDNS a orígenes LAN ya; evaluar con testing el scoping de DHCP antes de aplicarlo.

### 5.4 [MENOR] `/etc/u2f_mappings` shipped world-readable
**Archivos:** `lib/fido2.sh:42-43` (`sudo tee` + `sudo chmod 0644`), contraste con
`home/dot_local/bin/executable_archfrican-tpm-unlock:54` (`chmod 0600 /etc/crypttab.initramfs`)

0644 filtra qué usuarios tienen FIDO2 enrolado más sus key-handles/pubkeys a cualquier cuenta local.
pam_u2f sólo necesita root para leerlo.

**Acción:** cambiar a `chmod 0600` en `lib/fido2.sh:42-43`.

### 5.5 [MENOR] Path 'script:' pipea instalador remoto a bash sin verificación
**Archivos:** `home/dot_local/bin/executable_archfrican-defaults:57` (`curl -fsSL '$pkg' | bash`),
`:114` (`script:https://claude.ai/install.sh`), contraste con `modules/00-base.sh:14-21` (pin de
fingerprint CachyOS)

Patrón clásico curl-pipe-to-shell sin checksum. **Caveat:** pinnear un hash de un instalador dinámico de
vendor es frágil (re-verificar en cada update upstream).

**Acción:** fix ligero — mostrar una advertencia explícita en pantalla antes de correr entradas
`script:`, distinguiéndolas de los paths repo/aur verificados por GPG.

---

## 6. Nuevas funcionalidades (UX diaria de desarrollo)

### 6.1 [IMPORTANTE] Sin badge ambiental de GitHub/GitLab (reviews de PR, estado CI, menciones)
**Archivos:** `home/dot_local/bin/executable_archfrican-git:86-104` (único touchpoint GitHub: wizard
`gh auth login`/`gh ssh-key add`), `modules/70-hygiene.sh:86-105` (patrón timer `--user` horario),
`home/dot_config/waybar/config.jsonc` + `executable_archfrican-net-status` (patrón custom/ JSON)

Grep confirma cero features de notificación GitHub. Nada cubre 'me pidieron review' / 'CI falló' /
'@mención'.

**Acción:** nuevo módulo gh-poller reusando el patrón waybar custom/JSON + timer `--user` horario ya
establecido.

### 6.2 [IMPORTANTE] `archfrican-displays` tiene un único layout global, sin perfiles docked/undocked
**Archivos:** `home/dot_local/bin/executable_archfrican-displays:24` (SIDE = path único
`.archfrican-displays.kdl`), `:32-44` (gen_blocks deriva de `niri msg --json outputs`)

`save` siempre sobreescribe y `restore` (sólo desde chezmoi run_after, sin trigger de hotplug)
re-splicea lo último guardado. `niri msg --json outputs` ya provee un fingerprint estable de conectores
que no se usa.

**Acción:** keyar el layout guardado por el set de outputs conectados (fingerprint de conectores) y
auto-seleccionar el perfil correcto; opcionalmente un trigger de hotplug. (Esfuerzo grande.)

### 6.3 [IMPORTANTE] Sin project-jumper zero-config distinto de las sesiones pre-autoradas
**Archivos:** `home/dot_local/bin/executable_archfrican-session:2-4,14-22` (sólo lee
`~/.config/archfrican/sessions/<name>.session` hand-authored), `home/dot_zshrc:30` (zoxide wired pero
sólo lo consume la shell interactiva), `home/dot_config/niri/config.kdl.tmpl` (Mod+Shift+O libre)

No hay modo frecency/ad-hoc.

**Acción:** nuevo binario que consuma la DB de zoxide fuera de la shell (picker fuzzel) bindeado a
Mod+Shift+O.

### 6.4 [MENOR] Sin 'modo presentación/reunión' combinado (focus + caffeine + DND)
**Archivos:** `home/dot_local/bin/executable_archfrican-focus`, `executable_archfrican-caffeine`,
`executable_archfrican-privacy-indicator` — los tres independientes, sin cross-calls

**Acción:** nuevo `archfrican-present` que orqueste focus + caffeine + swaync DND en un solo toggle.

### 6.5 [MENOR] Sin pre-commit hook local que espeje shellcheck/bash -n de CI
**Archivos:** `.git/hooks` (sólo `*.sample`), `CONTRIBUTING.md:56` (instrucción manual `bash -n` +
`shellcheck -x -e SC1091`), `.github/workflows/ci.yml:12-31` (única enforcement, tras push)

**Acción:** añadir un pre-commit hook instalable que corra los mismos `bash -n`/`shellcheck` de
`ci.yml:12-31` localmente.

### 6.6 [MENOR] Sin comando scaffold de nuevo proyecto ('archfrican-new')
**Archivos:** `docs/CONTEXT.md:14` (workflow polyglot declarado), `packages/dev.txt` (rustup/go/uv/fnm/
direnv), `home/dot_zshrc:31-32` (fnm+direnv), `executable_archfrican-webapp` (único 'new X')

**Acción:** nuevo `archfrican-new` reusando el idiom interactivo de `archfrican-webapp`, generando
scaffold + `.envrc` direnv por lenguaje.

### 6.7 [MENOR] Sin sync cross-máquina de secretos de dev (tokens npm/PyPI, creds cloud)
**Archivos:** `home/dot_local/bin/executable_archfrican-migrate:19-28` (do_keys: `cp` sin cifrar de
.ssh/.gnupg), `docs/MODULES.md:218` (sugerencia Bitwarden comentada), `docs/COMMANDS.md:150-156`
(patrón restic-pass de archfrican-backup)

**Acción:** añadir sync cifrado (chezmoi age / restic-pass como precedente) para tokens y creds cloud.

---

## 7. Qué se descartó y por qué

No se descartó ningún finding en esta ronda: los seis auditores triaron sus candidatos contra el código
real antes de reportar, y todos los que llegaron a este informe fueron re-verificados (varios
reproducidos en vivo — el `eval` de multiboot, los timeouts de systemd, los tiempos de init de shell).
Donde el finder original tenía imprecisiones menores de conteo o número de línea, se corrigieron en la
evidencia citada arriba sin invalidar el finding.

---

## 8. Punch list priorizada (por ratio impacto/esfuerzo)

1. **`lib/multiboot.sh:73`** — eliminar `eval`, parsear lsblk en JSON. Crítico, esfuerzo pequeño, RCE
   root reproducido. *(Empezar aquí.)*
2. **`archfrican-backup:50-56`** — añadir `TimeoutStartSec=infinity` a la unit. Crítico, una línea.
3. **`bin/archfrican-update:190-193`** — añadir `-t 25000` a `notify-send`. Elimina el AMBER recurrente.
4. **`home/dot_zshrc:30-36`** — diferir los 5 inits de shell con `wait lucid`.
5. **`lib/converge.sh:31`** — añadir `lib/grub.sh` a los inputs de 40-theming.
6. **`lib/fido2.sh:42-43`** — `chmod 0600` en u2f_mappings.
7. **`modules/60-security.sh:38`** — `policy drop` en la chain forward.
8. **`home/dot_config/waybar/config.jsonc:84`** + doctor — sacar los checks de red del poll de 30min.
9. **`executable_archfrican-net-status:8`** / config connectivity — subir intervalo / usar estado de
   enlace.
10. **Módulo phase2:** envolver fetches de red en `timeout` (`00-base.sh:9`, `30-dev.sh:9-10`,
    `common.sh:213`, `35-apps.sh:15,27`).
11. **CI:** guarda de consistencia de las 5 listas de módulos.
12. **`tests/unit/converge.sh` + `tests/unit/defaults.sh`** — cubrir los dos motores núcleo sin tests.
13. **`iso.yml`** — gate de validación estructural (unsquashfs + tamaño) antes de publicar la nightly.
14. **Single-source de las 57 entradas de menú** (`archfrican-actions` ↔ `actions.toml.tmpl`).
15. **Extraer `modules/15-desktop-services.sh`** de `20-niri-desktop.sh`.
16. **Lib compartida `have()/note()`/confirm-dialog** sourceada por los ~26 scripts.
17. **`flock` en el pipeline de `archfrican-update`** (git/pacman/converge).
18. **Feature: gh-poller badge de atención** (reviews/CI/menciones).
19. **Feature: project-jumper zoxide** en Mod+Shift+O.
20. **Feature: perfiles docked/undocked** en `archfrican-displays` (esfuerzo grande, alto impacto diario).

Menores restantes (agrupar en limpieza): batching pacman/flatpak (2.5, 2.6), migrar privacy a pw-mon
(2.3), accessor de markers phase1↔phase2 (3.6), split power/microcode de 60-security (3.7), tests de
health/wallpaper (4.4, 4.5), doc del subcomando update (4.6), guarda de invariante D-Bus (4.3), warning
en path `script:` (5.5), scoping de mDNS (5.3), pre-commit hook (6.5), `archfrican-new` (6.6), modo
presentación (6.4), sync de secretos cifrados (6.7).
