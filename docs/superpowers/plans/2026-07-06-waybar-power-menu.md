# Waybar Power/System Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Bloquear/Cerrar sesión/Suspender/Reiniciar/Apagar to the existing `archfrican-actions`
control-center menu (both its fuzzel-fallback script and its native Walker/elephant TOML provider),
and surface it via a new power button in waybar.

**Architecture:** No new script. Two existing menu-definition files
(`home/dot_local/bin/executable_archfrican-actions` and
`home/dot_config/elephant/menus/actions.toml.tmpl`) each get 5 new entries inserted at the top of
their list, describing the same 5 actions in their respective syntaxes. A new static
`custom/power` waybar module is appended to `modules-right`, whose `on-click` simply runs
`archfrican-actions` — the script itself already decides Walker-native vs. fuzzel-fallback, so
waybar doesn't need to know which.

**Tech Stack:** bash (`set -euo pipefail` scripts), TOML (chezmoi `.tmpl`, Go-template
placeholders), JSONC (waybar config), fuzzel `--dmenu`, niri IPC (`niri msg action`), systemd
(`systemctl suspend/reboot/poweroff`).

## Global Constraints

- **No `sudo`** on any of the new `systemctl`/`niri msg` commands — the active desktop session is
  already authorized via polkit/logind for suspend/reboot/poweroff, and adding `sudo` would trigger
  an unwanted password prompt that breaks a one-click menu (spec: "Sin sudo en los comandos de
  energía").
- **Confirm only the 3 destructive/session-ending actions** — Cerrar sesión, Reiniciar, Apagar.
  Bloquear pantalla and Suspender run immediately, no confirmation step (spec: "Sin confirmación en
  Bloquear ni Suspender").
- **Confirmation UX text is `"Sí, <acción>"` / `"Cancelar"`**, prompt label `confirmar` — copied
  verbatim from the existing pattern in `home/dot_local/bin/executable_archfrican-rollback:20-21`
  (verified byte-for-byte via `od -c`: plain ASCII, no hidden glyph — `'  confirmar  '`, two
  literal spaces on each side of the word, nothing else).
- **The 5 new items go at the very top** of both lists, in this exact order: Bloquear pantalla,
  Cerrar sesión, Suspender, Reiniciar, Apagar (spec table order).
- **Both frontends must describe the same 5 actions** — a change to one without the matching
  change to the other is a spec violation (this is explicitly why Tasks 1 and 2 below mirror each
  other).

---

### Task 1: Add the 5 actions to the fuzzel-fallback script

**Files:**
- Modify: `home/dot_local/bin/executable_archfrican-actions:9` (add a `confirm()` helper next to
  the existing `toggle()` helper), `:18` (top of the `printf` item list), `:73` (top of the `case`
  statement, right before the existing `"Asistente"*)` branch)

**Interfaces:**
- Produces: a shell function `confirm(msg)` — takes one argument (a lowercase Spanish phrase like
  `"reiniciar ahora"`), shows a fuzzel confirmation dmenu, returns 0 (confirmed) or 1 (cancelled/
  Escape). Task 3's live end-to-end verification calls into this indirectly (via the menu), no
  other task calls it directly.

- [ ] **Step 1: Confirm the current line numbers still match before editing**

Run: `grep -n "^toggle\|^sel=\|\"Asistente\"\*" home/dot_local/bin/executable_archfrican-actions`

Expected output (if the file hasn't changed since this plan was written):
```
9:toggle() { [ "$("$1" status 2>/dev/null)" = on ] && echo off || echo on; }
17:sel="$(printf '%s\n' \
73:  "Asistente"*)          "$B/archfrican-setup" ;;
```
(Line 17 is the `sel="$(printf ...` opener; line 18 is the first item `"Asistente de
configuración (todo)…"`.) If the numbers differ, locate the same three anchors by content instead
of line number before proceeding.

- [ ] **Step 2: Add the `confirm()` helper right after `toggle()`**

Using the Edit tool, change:
```bash
toggle() { [ "$("$1" status 2>/dev/null)" = on ] && echo off || echo on; }
```
to:
```bash
toggle() { [ "$("$1" status 2>/dev/null)" = on ] && echo off || echo on; }
confirm() {   # confirm "reiniciar ahora" -> 0 si el usuario confirma, 1 si cancela/Escape
  local c
  c="$(printf 'Sí, %s\nCancelar\n' "$1" | fuzzel --dmenu --prompt '  confirmar  ')" || return 1
  case "$c" in "Sí,"*) return 0 ;; *) return 1 ;; esac
}
```

- [ ] **Step 3: Verify the script still parses**

Run: `bash -n home/dot_local/bin/executable_archfrican-actions`
Expected: no output, exit code 0.

- [ ] **Step 4: Insert the 5 new items at the top of the `printf` list**

Using the Edit tool, change:
```bash
sel="$(printf '%s\n' \
  "Asistente de configuración (todo)…" \
```
to:
```bash
sel="$(printf '%s\n' \
  "Bloquear pantalla" \
  "Cerrar sesión" \
  "Suspender" \
  "Reiniciar" \
  "Apagar" \
  "Asistente de configuración (todo)…" \
```

- [ ] **Step 5: Verify the script still parses**

Run: `bash -n home/dot_local/bin/executable_archfrican-actions`
Expected: no output, exit code 0.

- [ ] **Step 6: Insert the 5 new `case` branches right before the existing `"Asistente"*)` branch**

Using the Edit tool, change:
```bash
case "$sel" in
  "Asistente"*)          "$B/archfrican-setup" ;;
```
to:
```bash
case "$sel" in
  "Bloquear pantalla"*)  "$B/archfrican-lock" ;;
  "Cerrar sesión"*)      confirm "cerrar sesión" && niri msg action quit ;;
  "Suspender"*)          systemctl suspend ;;
  "Reiniciar"*)          confirm "reiniciar ahora" && systemctl reboot ;;
  "Apagar"*)             confirm "apagar ahora" && systemctl poweroff ;;
  "Asistente"*)          "$B/archfrican-setup" ;;
```

- [ ] **Step 7: Verify the script still parses**

Run: `bash -n home/dot_local/bin/executable_archfrican-actions`
Expected: no output, exit code 0.

- [ ] **Step 8: Manually exercise the `confirm()` helper in isolation**

Run:
```bash
bash -c '
source <(sed -n "/^confirm()/,/^}/p" home/dot_local/bin/executable_archfrican-actions)
if confirm "probar esto"; then echo CONFIRMED; else echo CANCELLED; fi
'
```
This opens a real fuzzel dmenu reading `Sí, probar esto` / `Cancelar`. Pick `Sí, probar esto` —
expected output: `CONFIRMED`. Run it again and pick `Cancelar` (or press Escape) — expected
output: `CANCELLED`.

- [ ] **Step 9: Commit**

```bash
git add home/dot_local/bin/executable_archfrican-actions
git commit -m "feat(actions): add power/session actions to the fuzzel fallback menu

Bloquear pantalla, Cerrar sesión, Suspender, Reiniciar, Apagar — the
5 actions the control-center menu was missing. Reiniciar/Apagar/Cerrar
sesión confirm first, matching archfrican-rollback's existing pattern."
```

---

### Task 2: Mirror the 5 actions into the native Walker/elephant TOML provider

**Files:**
- Modify: `home/dot_config/elephant/menus/actions.toml.tmpl:6` (insert 5 new `[[entries]]` blocks
  right before the existing `[[entries]] / text = "Asistente de configuración (todo)…"` block)

**Interfaces:**
- Consumes: nothing from Task 1 (this is an independent frontend describing the same actions in
  TOML — the two files intentionally duplicate the action list, per the spec's "dos frontends,
  deben quedar sincronizados").
- Produces: the entries Task 3's live end-to-end test exercises through `Mod+Shift+A` /
  the waybar button, when Walker + elephant are running (the actual day-to-day path on this
  machine).

- [ ] **Step 1: Confirm the current anchor still matches before editing**

Run: `grep -n "\[\[entries\]\]\|Asistente de configuración" home/dot_config/elephant/menus/actions.toml.tmpl | head -3`

Expected:
```
6:[[entries]]
7:text = "Asistente de configuración (todo)…"
```

- [ ] **Step 2: Insert the 5 new `[[entries]]` blocks before that one**

Using the Edit tool, change:
```toml
fixed_order = true

[[entries]]
text = "Asistente de configuración (todo)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-setup" }
```
to:
```toml
fixed_order = true

[[entries]]
text = "Bloquear pantalla"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-lock" }

[[entries]]
text = "Cerrar sesión"
actions = { run = "sh -c 'c=$(printf \"Sí, cerrar sesión\\nCancelar\\n\" | fuzzel --dmenu --prompt \"  confirmar  \"); case \"$c\" in \"Sí,\"*) niri msg action quit ;; esac'" }

[[entries]]
text = "Suspender"
actions = { run = "systemctl suspend" }

[[entries]]
text = "Reiniciar"
actions = { run = "sh -c 'c=$(printf \"Sí, reiniciar ahora\\nCancelar\\n\" | fuzzel --dmenu --prompt \"  confirmar  \"); case \"$c\" in \"Sí,\"*) systemctl reboot ;; esac'" }

[[entries]]
text = "Apagar"
actions = { run = "sh -c 'c=$(printf \"Sí, apagar ahora\\nCancelar\\n\" | fuzzel --dmenu --prompt \"  confirmar  \"); case \"$c\" in \"Sí,\"*) systemctl poweroff ;; esac'" }

[[entries]]
text = "Asistente de configuración (todo)…"
actions = { run = "{{ .chezmoi.homeDir }}/.local/bin/archfrican-setup" }
```

- [ ] **Step 3: Render the template through chezmoi and validate it's well-formed TOML**

Run:
```bash
chezmoi execute-template < home/dot_config/elephant/menus/actions.toml.tmpl \
  | python3 -c "import tomllib, sys; tomllib.load(sys.stdin.buffer); print('OK: valid TOML')"
```
Expected output: `OK: valid TOML` (a `tomllib.TOMLDecodeError` traceback means a quoting mistake
in one of the new `run = "sh -c '...'"` lines — re-check the escaping character-by-character
against the block above, TOML requires every literal `"` inside the double-quoted `run` string to
be `\"`, and every literal `\n` destined for the shell's `printf` to be written as `\\n`).

- [ ] **Step 4: Spot-check the rendered `run` command actually parses as shell**

Run:
```bash
chezmoi execute-template < home/dot_config/elephant/menus/actions.toml.tmpl \
  | python3 -c "
import sys, tomllib
data = tomllib.load(sys.stdin.buffer)
for e in data['entries']:
    if e['text'] in ('Cerrar sesión', 'Reiniciar', 'Apagar'):
        print(e['text'], '->', e['actions']['run'])
"
```
For each of the 3 printed commands, pipe it into `bash -n`:
```bash
echo '<paste the printed command here>' | bash -n
```
Expected: no output, exit code 0, for all 3.

- [ ] **Step 5: Commit**

```bash
git add home/dot_config/elephant/menus/actions.toml.tmpl
git commit -m "feat(actions): mirror power/session actions into the native Walker menu

Same 5 entries as the fuzzel fallback (archfrican-actions), described
as elephant menu TOML entries so Mod+Shift+A shows them when
Walker/elephant are running (the actual day-to-day path)."
```

---

### Task 3: Add the waybar power button and verify end-to-end

**Files:**
- Modify: `home/dot_config/waybar/config.jsonc:17` (append `"custom/power"` to `modules-right`),
  end of file after the `"tray"` module definition (add the new `"custom/power"` block)

**Interfaces:**
- Consumes: `home/dot_local/bin/executable_archfrican-actions` (Task 1) as its `on-click` target —
  no interface beyond "runs this path with no arguments," so this task has no hard ordering
  dependency on Tasks 1/2 being merged first, but the live end-to-end test in Step 6 below is only
  meaningful once they are.

- [ ] **Step 1: Generate the verified power-off glyph bytes**

The Nerd Font power-off character (nf-fa-power-off, Unicode U+F011) is a Private-Use-Area code
point that does not reliably survive being retyped by hand or pasted through some text channels —
this exact problem already happened once while writing the design spec (`git log --oneline -1` on
commit `d582448` fixes an earlier empty-icon bug). Generate it from the codepoint instead of typing
it:

```bash
python3 -c "print(chr(0xf011))" | od -c
```
Expected output: `357 200 221  \n` (3 UTF-8 bytes: `0xEF 0x80 0x91`). If your terminal renders a
glyph on the line above the `od -c` output, that glyph is correct and safe to copy from THAT
terminal's rendering for the next step — but if you cannot visually confirm it, use the byte
sequence directly:
```bash
printf '\xef\x80\x91'
```
Both commands above must produce identical bytes — cross-check with `od -c` before using either
output in Step 2.

- [ ] **Step 2: Confirm current anchors before editing**

Run: `grep -n '"modules-right"\|"tray": { "spacing"' home/dot_config/waybar/config.jsonc`

Expected:
```
12:  "modules-right": [
130:  "tray": { "spacing": 8 }
```
(Line 17, inside that array, ends with `"custom/caffeine", "custom/health", "custom/notification", "tray"`.)

- [ ] **Step 3: Append `"custom/power"` to `modules-right`**

Using the Edit tool, change:
```jsonc
    "custom/caffeine", "custom/health", "custom/notification", "tray"
  ],
```
to:
```jsonc
    "custom/caffeine", "custom/health", "custom/notification", "tray", "custom/power"
  ],
```

- [ ] **Step 4: Add the `custom/power` module definition after `tray`**

Using the Edit tool, change:
```jsonc
  "tray": { "spacing": 8 }
}
```
to (replace `<GLYPH>` with the literal 3-byte character generated in Step 1 — do not type it from
memory, paste the verified output):
```jsonc
  "tray": { "spacing": 8 },
  // power/system menu — nf-fa-power-off, U+F011 (see docs/superpowers/specs/2026-07-06-waybar-power-menu-design.md)
  "custom/power": {
    "format": "<GLYPH>",
    "tooltip-format": "Energía / sistema",
    "on-click": "$HOME/.local/bin/archfrican-actions"
  }
}
```

- [ ] **Step 5: Validate the JSONC still parses (stripping `//` comments first, since plain `json` doesn't allow them)**

Run:
```bash
python3 -c "
import json, re
with open('home/dot_config/waybar/config.jsonc') as f:
    text = f.read()
text = re.sub(r'//.*', '', text)
data = json.loads(text)
assert 'custom/power' in data['modules-right'], 'custom/power missing from modules-right'
assert data['custom/power']['format'], 'custom/power format is empty — the glyph did not survive, redo Step 1'
print('OK: valid JSON, custom/power wired in, glyph present')
"
```
Expected output: `OK: valid JSON, custom/power wired in, glyph present`. If the assertion about the
empty format string fires, the glyph was lost again — go back to Step 1 and use the `printf`
byte-sequence method directly instead of copy-pasting a rendered character.

- [ ] **Step 6: Reload waybar and verify live**

Run:
```bash
pkill -SIGUSR1 waybar || systemctl --user restart waybar.service
journalctl --user -u waybar.service -n 20 --no-pager
```
Expected: no `Error parsing config` or similar lines in the last 20 journal lines. Then look at the
physical bar: a new icon should appear at the far right, after the tray. Hover it — tooltip reads
"Energía / sistema". Click it — the same menu that `Mod+Shift+A` opens appears, with **Bloquear
pantalla / Cerrar sesión / Suspender / Reiniciar / Apagar** as the first 5 items.

- [ ] **Step 7: Verify the underlying suspend/reboot/poweroff commands are valid, without actually
  performing them**

`systemctl` has a real `--dry-run` flag (confirmed via `systemctl --help`, which lists it as
"Only print what would be done. Currently supported by verbs: halt, poweroff, reboot, kexec,
soft-reboot, suspend, hibernate, suspend-then-hibernate, hybrid-sleep, default…") — note the flag
goes **before** the verb, not after. Run all three directly (safe — nothing actually happens):

```bash
systemctl --dry-run suspend;  echo "suspend exit: $?"
systemctl --dry-run reboot;   echo "reboot exit: $?"
systemctl --dry-run poweroff; echo "poweroff exit: $?"
```
Expected: each prints what it *would* do and exits 0, with no actual suspend/reboot/poweroff
happening. This proves the exact verbs used in Task 1/2's case branches (`systemctl suspend`,
`systemctl reboot`, `systemctl poweroff`) are valid systemd unit-manager commands the active
session is authorized to run.

- [ ] **Step 8: Exercise every new action from the live menu**

From the waybar button (or `Mod+Shift+A`):
- Pick **Bloquear pantalla** — screen locks immediately, no confirmation prompt. Unlock with your
  password to continue testing.
- Pick **Suspender** ONLY if you're prepared for the machine to actually suspend right now (there
  is no confirmation gate on this one, by design — Step 7 already proved the underlying command is
  correct, so actually exercising it here is optional, not required to pass this task).
- Pick **Cerrar sesión** — a confirmation dmenu appears (`Sí, cerrar sesión` / `Cancelar`). Pick
  `Cancelar` — nothing happens (session stays open). Do NOT confirm this one during testing unless
  you're prepared to log back in through SDDM.
- Pick **Reiniciar** — confirmation dmenu appears (`Sí, reiniciar ahora` / `Cancelar`). Pick
  `Cancelar` — nothing happens. Do NOT confirm unless you intend to actually reboot.
- Pick **Apagar** — confirmation dmenu appears (`Sí, apagar ahora` / `Cancelar`). Pick `Cancelar`
  — nothing happens. Do NOT confirm unless you intend to actually power off.

For all three confirm-gated actions, cancelling must be silently safe (no side effect, no error
notification) — that's the pass condition for this step, without needing to actually reboot/
poweroff/logout the live machine mid-test.

- [ ] **Step 9: Force the fuzzel-fallback path and verify the same 5 items there too**

The spec requires both frontends to work — Steps 6-8 above exercised the **native Walker path**
(what's actually running day-to-day on this machine). Now force `archfrican-actions`'s fallback
branch (`command -v walker >/dev/null 2>&1 && elephant listproviders ... | grep -q
"^desktopapplications$"`) to fail, by shadowing `elephant` with a stub that always exits 1, using
this session's scratchpad directory (never write test scaffolding into `/tmp` directly or into the
repo):

```bash
SCRATCH="/tmp/claude-1000/-home-jafricanot-Developer-Archfrican/162fb9df-0b5f-48cc-9985-db3841ca41e5/scratchpad"
mkdir -p "$SCRATCH/fake-bin"
printf '#!/bin/sh\nexit 1\n' > "$SCRATCH/fake-bin/elephant"
chmod +x "$SCRATCH/fake-bin/elephant"
PATH="$SCRATCH/fake-bin:$PATH" "$HOME/.local/bin/archfrican-actions"
```
Expected: this opens the **fuzzel** dmenu instead of Walker's native popover, still showing
**Bloquear pantalla / Cerrar sesión / Suspender / Reiniciar / Apagar** as the first 5 items. Repeat
the same cancel-only exercise as Step 8 (pick each of the 3 confirm-gated actions, cancel each one,
confirm no side effect) to prove the fuzzel-side `case` branches and the `confirm()` helper work
identically to the TOML side. Clean up afterwards: `rm -rf "$SCRATCH/fake-bin"`.

- [ ] **Step 10: Commit**

```bash
git add home/dot_config/waybar/config.jsonc
git commit -m "feat(waybar): add a power/system button

Appends custom/power to the right end of the bar; on-click opens the
same archfrican-actions control center as Mod+Shift+A, now including
the lock/logout/suspend/reboot/poweroff actions added in the previous
two commits."
```

---

## Final check

- [ ] Re-read the spec (`docs/superpowers/specs/2026-07-06-waybar-power-menu-design.md`) once more
  top to bottom and confirm every "Sí cubre" bullet has a corresponding completed task above.
- [ ] `git log --oneline -4` shows the 3 feature commits (Tasks 1-3) plus the earlier spec fix,
  all without any Claude/AI/co-author attribution (per this repo's standing commit-practices rule).
