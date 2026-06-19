# Security Policy / Política de seguridad

> 🇬🇧 English first · 🇪🇸 Español a continuación.

## English

### Reporting a vulnerability
**Please do not open a public issue for security problems.** Report privately via:
- a **GitHub private security advisory** (Security → *Report a vulnerability*), or
- **email: josefranciscoat.correo@gmail.com**.

You'll get an acknowledgement as soon as the maintainer can; this is a personal project with no SLA and
**no bug bounty**. Please include what's affected, how to reproduce, and the impact.

### Scope
Archfrican is an **installer that runs as root and partitions disks**, so the highest-value targets are:
disk/partitioning + the bootloader, encryption/LUKS, authentication (PAM / sudo / FIDO2), the firewall, and
the **supply chain** (the `curl | sh` bootstrap, the CachyOS repo bootstrap, AUR builds).

### Current posture (where the safety lives)
- **Supply chain** — the CachyOS repo tarball (run as root) is verified **fail-closed** against the
  pinned CachyOS **GPG signing-key fingerprint** (`882DCFE4…8DB35A47`, in `modules/00-base.sh`): its
  detached `.sig` is checked before the bootstrap runs. The fingerprint is the stable trust anchor —
  it doesn't rotate when the tarball is rebuilt, so there's no per-release pin to maintain. paru is
  required from the signed CachyOS binary repo.
- **Disk** — the ISO installer **defaults to a dry-run preview** (`ARCHFRICAN_ISO_ARMED` defaults to `0`; a
  real install is an explicit env/interactive opt-in) and `confirm_wipe` makes you retype the device name
  before any format. CI enforces the committed default stays `0`.
- **Auth** — FIDO2 is **non-exclusive** (a key *or* the password always works — no lockout) and refuses
  `pam-u2f < 1.3.1` (CVE-2025-23013); root is disabled (sudo-only); sudoers drop-ins are `visudo -cf`
  validated; passwords flow via stdin only.
- **Network** — the nftables firewall uses a **named table and never `flush ruleset`** (so it can't wipe
  Docker/podman tables), deny-inbound by default.
- The full audit trail lives in [docs/audit/](docs/audit/).

Validated findings and fixes are tracked in the audit and in `docs/*`. Out-of-scope: vulnerabilities in
upstream Arch/CachyOS/AUR packages themselves — report those upstream.

## Español

### Reportar una vulnerabilidad
**Por favor no abras un issue público para problemas de seguridad.** Repórtalo en privado vía:
- un **aviso de seguridad privado de GitHub** (Security → *Report a vulnerability*), o
- **correo: josefranciscoat.correo@gmail.com**.

Recibirás acuse de recibo en cuanto el mantenedor pueda; es un proyecto personal sin SLA y **sin
recompensas (bug bounty)**. Incluye qué está afectado, cómo reproducirlo y el impacto.

### Alcance
Archfrican es un **instalador que corre como root y particiona discos**, así que los objetivos de mayor
valor son: disco/particionado + el bootloader, cifrado/LUKS, autenticación (PAM / sudo / FIDO2), el firewall
y la **cadena de suministro** (el bootstrap `curl | sh`, el repo de CachyOS, las builds de AUR).

### Postura actual (dónde vive la seguridad)
- **Cadena de suministro** — el tarball del repo CachyOS (se corre como root) se verifica **fail-closed**
  contra el **fingerprint de la clave de firma GPG** de CachyOS fijado (`882DCFE4…8DB35A47`, en
  `modules/00-base.sh`): se comprueba su firma `.sig` antes de ejecutar el bootstrap. El fingerprint es
  el ancla de confianza estable — no rota cuando se reconstruye el tarball, así que no hay pin por
  versión que mantener. paru se exige desde el repo binario firmado de CachyOS.
- **Disco** — el instalador ISO **sale en preview/dry-run por defecto** (`ARCHFRICAN_ISO_ARMED` por defecto
  `0`; un install real es opt-in explícito por env/interactivo) y `confirm_wipe` exige reescribir el nombre
  del dispositivo antes de cualquier formateo. CI asegura que el default commiteado siga en `0`.
- **Auth** — FIDO2 es **no excluyente** (la llave *o* la contraseña siempre funcionan — sin lockout) y
  rechaza `pam-u2f < 1.3.1` (CVE-2025-23013); root deshabilitado (solo sudo); los drop-ins de sudoers se
  validan con `visudo -cf`; las contraseñas fluyen solo por stdin.
- **Red** — el firewall nftables usa una **tabla nombrada y nunca `flush ruleset`** (no puede borrar las
  tablas de Docker/podman), deny-inbound por defecto.
- El rastro completo de auditoría está en [docs/audit/](docs/audit/).

Fuera de alcance: vulnerabilidades en los propios paquetes upstream de Arch/CachyOS/AUR — repórtalas
upstream.
