# Contexto del proyecto — Instalador "Archfrican" (Arch + niri, estilo Omarchy)

> Pega este documento al inicio de una conversación para retomar el proyecto con
> contexto completo. Resume **qué** se decidió, **por qué**, **qué ya está construido**
> y **qué falta**. Las versiones/URLs eran vigentes a mediados de 2026; reverifícalas.

---

## 1. Objetivo

Construir un instalador personal para Arch Linux en el espíritu de **Omarchy** (DHH):
opinado y fácil de levantar, pero **100% personalizado** a mis preferencias y, sobre
todo, **extremadamente fiable** ("que nada explote ni bugs raros"). El equipo enfocado
es **programación de alto rendimiento** (polyglot). Nombre del proyecto: **Archfrican**
(renombrable si haces un fork).

## 2. Principios de diseño (rectores)

1. **Dos capas separadas, nunca mezcladas**: sistema (Arch + paquetes) vs configuración (dotfiles).
2. **Modular y desacoplado**: cada componente (compositor, terminal, shell, editor) vive
   aislado en su módulo + lista de paquetes + dotfiles, para poder **cambiarlo en el futuro
   sin romper el resto**. Requisito explícito del usuario.
3. **GPU-agnóstico**: el mismo instalador corre en AMD/Intel/NVIDIA/híbrida vía auto-detección.
4. **Fiabilidad primero**: snapshots con rollback, kernel dual con red de seguridad, y
   **cero plugins frágiles** de compositor.

## 3. Decisiones tomadas (con su razón)

| Área | Decisión | Por qué |
|------|----------|---------|
| Base | Arch vanilla **+ repos CachyOS** (no CachyOS completo) | Control y predecibilidad de Arch + perks de Cachy (LTO/BOLT, x86-64-v3/v4, scheduler). Ganancia real para *compiles* es modesta; no sobre-optimizar la base. |
| Kernel | `linux-cachyos` (principal) + `linux-lts` (fallback en GRUB) | Red de seguridad: si un kernel Cachy pelea con NVIDIA, se arranca LTS y se sigue trabajando. |
| Filesystem | Btrfs + snapper + snap-pac + grub-btrfs | Rollback en **un reboot** si un update rompe algo. Es la palanca #1 de fiabilidad. |
| Compositor | **niri** (puro), modular/swappable | Sobre Hyprland por fiabilidad: el scrolling es el núcleo (no un añadido), menor superficie de bugs, evita el churn de la migración a Lua de Hyprland 0.55 y la fragilidad de plugins (hyprscroller). El objetivo real es el *flujo* niri, no Hyprland. |
| GPU | NVIDIA principal, pero auto-detección AMD/Intel/híbrida | `nvidia-open-dkms` + `nvidia_drm.modeset=1` + early KMS. AMD/Intel = stack mesa abierto (lo más fiable). |
| Dotfiles | **chezmoi** | Bootstrap de un comando, templating (misma fuente → config por máquina/GPU), secretos. Nix+home-manager anotado como escalada futura si se quiere reproducibilidad total. |
| Login | greetd + tuigreet | Mínimo, Wayland-native, sin rarezas de DMs pesados. |
| Terminal | **Ghostty** (sobre Kitty) | UI nativa GTK4, zero-config, rendimiento top, soporta protocolo de imágenes de Kitty. niri ya gestiona el tiling, así que las features de ventanas de Kitty sobran. Es el componente con **menos lock-in**. |
| Shell | **Zsh** + zinit + fast-syntax-highlighting + zsh-autosuggestions + completions | Zsh por compatibilidad POSIX (no rompe scripts). **Sin oh-my-zsh** (lento, 400ms+). Setup ligero <50ms. |
| Prompt | **Starship** (sobre p10k) | Cross-shell: sobrevive a un cambio de shell, encaja con el principio de no-lock-in. p10k es solo-zsh. |
| Editor | **VS Code** (Wayland nativo), desacoplado vía LSP | Los language servers se instalan a nivel de sistema (`rust-analyzer`, `gopls`, `pyright`+`ruff`, `typescript-language-server`, `clangd`); VS Code es solo un frontend, intercambiable por Neovim/Helix/Zed sin reconfigurar. |
| Lenguajes | Rust/C/C++, Go, Python/datos-ML, JS/TS | Toolchains vía version managers (rustup, go, uv, fnm) en vez de versiones del sistema. |
| Periféricos | waybar, **fuzzel** (estilo Spotlight), mako, swaylock+swayidle, swww, grim+slurp, cliphist, **paru**, nwg-dock | Todos Wayland-native, niri-friendly, en módulos independientes (vetar cualquiera). |
| Estética | **macOS-like**, tema default `macos-dark` | Migración desde macOS con mínima fricción. Tahoe grafito + azul de sistema, fuentes **SF Pro + SF Mono**, GTK **WhiteSur** + iconos, cursores McMojave, **blur nativo de niri 26.04** (efecto vidrio). |
| Theming | **Switcher multi-tema en caliente** (estilo Omarchy) | `theme-switch <name>`. Temas: macos-dark, macos-light, catppuccin-mocha, tokyo-night. |
| Fricción macOS | **keyd**: ⌘+letra → Ctrl | Mantiene muscle-memory de copy/paste/save/quit. ⌘ sigue siendo el modificador de niri para combos **sin-letra y con Shift** → sin colisiones. + scroll natural, tap-to-click, gestos 3 dedos, ⌘+Space=launcher, ⌘+Tab=overview. |

### Regla de diseño clave (keybinds)
Para que keyd y niri no colisionen: **niri nunca usa `Mod+<letra>` a secas**. Solo
`Mod+<no-letra>` (Return, Space, flechas, números, comas) y `Mod+Shift+...`. Por eso,
p.ej., cerrar ventana = `Mod+Shift+Q`. keyd solo intercepta `⌘+<letra>` plano.

## 4. Arquitectura del repo

Instalación en **dos fases**: (1) `archinstall --config` para la base, reboot;
(2) `./install.sh` idempotente para todo lo demás.

```
archfrican/
├── install.sh            # orquestador fase 2 (idempotente; ./install.sh 30-dev corre un módulo)
├── bootstrap.sh          # entrada curl|bash
├── archinstall/          # user_config.json (Btrfs+subvols+snapper, kernel lts, GRUB)
├── lib/                  # common.sh (logging, pac_install idempotente) + detect-gpu.sh
├── modules/              # 00-base 10-gpu 20-niri-desktop 30-dev 40-theming 50-snapshots
├── packages/             # listas por capa: base / niri-desktop / dev / theming / aur
├── themes/<name>/colors.sh   # paletas (esquema único de variables)
├── templates/            # plantillas por app (placeholders ${VAR})
├── bin/theme-switch      # switcher en caliente (sed puro, sin dependencias)
└── home/                 # fuente de dotfiles chezmoi (dot_config/{niri,ghostty,waybar,fuzzel,mako,...}, dot_zshrc)
```

### Mecánica del theming
`theme-switch <name>` hace `source themes/<name>/colors.sh` → renderiza cada plantilla a
`~/.config/<app>/` (sed sobre `${VAR}`) → recarga en vivo (waybar SIGUSR2, `makoctl reload`,
niri auto-reload por marcadores `// THEME-START/END` en config.kdl). fuzzel usa hex **sin `#`**
(se hace strip aparte). Añadir tema = soltar un `colors.sh` con el mismo esquema de variables.

## 5. Estado actual (lo construido — v0)

- Esqueleto de **42 archivos** generado y entregado como `archfrican.zip`.
- Todos los scripts pasan `bash -n`.
- `theme-switch` **probado funcionando** y **idempotente** (cambios múltiples conservan
  marcadores; colores correctos en ghostty/fuzzel/mako/waybar y borde de niri).
- Switcher reescrito **sin dependencias** (sed, no envsubst/gettext) para que no rompa en máquina nueva.
- Es un **v0 para iterar**, no para correr a ciegas en hardware todavía.

## 6. Caveats / a verificar antes de usar en hardware

- **archinstall**: el esquema JSON cambia entre versiones → revisar el TUI antes de tocar el disco.
- **CachyOS**: verificar la URL del tarball del repo en `modules/00-base.sh` contra la doc oficial.
- **NVIDIA**: reiniciar tras la fase 2 antes de la primera sesión de niri.
- **WhiteSur** puede ser imperfecto en algunas apps Wayland (`nwg-look` para ajustar).
- Algunos keybinds de niri son no-estándar por la regla "sin Mod+letra" (documentado).

## 7. Próximos pasos abiertos

- Pulir el módulo `dev` (settings concretos de VS Code, configs de LSP por lenguaje).
- Afinar **nwg-dock** para un dock que se sienta de verdad como el de macOS.
- Más temas en el switcher.
- Explotar **templating de chezmoi** para generar config específica de GPU desde una sola fuente.
- Evaluar **DankMaterialShell** (shell pulido basado en niri) como capa opcional.

## 8. Datos de referencia (mediados 2026, reverificar)

- niri 26.04 añadió **blur**; tiene layout scrolling nativo y es estable/daily-drivable.
- Hyprland 0.55 (mayo 2026) migró de hyprlang a **Lua** (cambio rompedor) — razón de descartarlo.
- Hyprland tiene layout `scrolling` nativo desde 0.54 (alternativa descartada por preferir niri).
- Reliability de NVIDIA en Wayland mejoró mucho en niri desde 2025; aún requiere cuidado (modeset, resume).
