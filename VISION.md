# Vision & Objectives

> 🇬🇧 English first · 🇪🇸 Español a continuación.

## English

**Archfrican is a personal, reliability-first Arch Linux installer** built around the
[niri](https://github.com/YaLTeR/niri) scrolling compositor, with a **macOS-friendly** UX for people
migrating off the Mac. The north star: **nothing explodes.**

### Objectives
1. **Two layers, never mixed** — the *system* (Arch + packages) and the *configuration* (dotfiles via
   chezmoi) stay separate, each with the right tool.
2. **Modular & swappable** — every component (compositor, terminal, shell, editor) lives in exactly one
   module + package list + dotfiles subtree. Swap one without touching the rest.
3. **GPU-agnostic** — the same installer auto-detects and runs on AMD / Intel / NVIDIA / hybrid.
4. **Reliability first** — Btrfs + Snapper snapshots (one-reboot rollback), a dual kernel
   (linux-cachyos primary + **linux-lts** safety net), zero fragile compositor plugins, and a hard rule
   that destructive/auth/boot code is gated and validated before it ships.

(The canonical wording of these principles lives in [README.md](README.md#design-principles) — this file
quotes it so scope stays in one place.)

### Non-goals (explicit scope guardrails)
- **Not a general-purpose distro or installer** for arbitrary setups — it is opinionated and personal in
  origin.
- **Source-available, NONCOMMERCIAL — not "open source."** Licensed under
  [PolyForm Noncommercial 1.0.0](LICENSE); commercial use is not granted. Do not describe it as an OSI
  open-source project.
- **GRUB-only**, because the snapshot-rollback safety net depends on it. Multi-boot is offered as an
  **os-prober toggle (default OFF)**, not a choice of boot manager.
- **No install-alongside / repartitioning / shrinking** an existing OS — the ISO path wipes the chosen
  disk; multi-boot only *detects* an OS already present (typically on another disk).
- **Not meant to be run blind on real hardware** in v0 — disk/boot/auth changes are VM-validated first
  (see [docs/STAGE2-VALIDATION.md](docs/STAGE2-VALIDATION.md)).

## Español

**Archfrican es un instalador personal de Arch Linux, con la fiabilidad primero**, construido alrededor del
compositor scrolling [niri](https://github.com/YaLTeR/niri), con una experiencia **amigable para quien viene
de macOS**. La estrella polar: **que nada explote.**

### Objetivos
1. **Dos capas, nunca mezcladas** — el *sistema* (Arch + paquetes) y la *configuración* (dotfiles con
   chezmoi) van separados, cada uno con la herramienta correcta.
2. **Modular e intercambiable** — cada componente (compositor, terminal, shell, editor) vive en un único
   módulo + lista de paquetes + dotfiles. Se cambia uno sin tocar el resto.
3. **Agnóstico de GPU** — el mismo instalador autodetecta y corre en AMD / Intel / NVIDIA / híbrida.
4. **Fiabilidad primero** — snapshots Btrfs + Snapper (rollback en un reinicio), kernel dual
   (linux-cachyos primario + **linux-lts** de red de seguridad), cero plugins frágiles de compositor, y la
   regla dura de que el código destructivo/de auth/de arranque está gateado y validado antes de publicarse.

### No-objetivos (límites de alcance explícitos)
- **No es una distro/instalador de propósito general** — es opinado y de origen personal.
- **Código disponible, NO COMERCIAL — no es "open source".** Bajo
  [PolyForm Noncommercial 1.0.0](LICENSE); no se concede uso comercial. No lo describas como proyecto
  open source de la OSI.
- **Solo GRUB**, porque la red de seguridad de rollback por snapshots depende de él. El multi-boot es un
  **toggle de os-prober (apagado por defecto)**, no una elección de gestor de arranque.
- **Sin instalar-junto-a / reparticionar / encoger** un SO existente — la ruta ISO borra el disco elegido;
  el multi-boot solo *detecta* un SO ya presente (típicamente en otro disco).
- **No pensado para correrse a ciegas en hardware real** en v0 — los cambios de disco/arranque/auth se
  validan primero en VM (ver [docs/STAGE2-VALIDATION.md](docs/STAGE2-VALIDATION.md)).
