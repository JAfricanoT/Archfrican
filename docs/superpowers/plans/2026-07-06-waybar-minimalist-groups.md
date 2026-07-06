# Waybar Minimalist Groups + Icon Font Unity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redistribute waybar's 14 flat `modules-right` entries into 4 visually separated sections
(volume, system, connectivity, status) inside one island, and unify every glyph in the bar to a
single Nerd Font instead of the current mix (Font Awesome + Material Design Icons + plain Unicode
bullets + a completely empty weather icon table).

**Architecture:** `home/dot_config/waybar/config.jsonc`'s `modules-right` array shrinks from 14
entries to 4 (`pulseaudio` + three native Waybar `group/*` modules), each `group` wrapping the
existing modules with zero change to their own config. `pulseaudio` drops its inline `{volume}%`
in favor of a tooltip (same pattern already used by `disk`). `home/dot_config/waybar/style.css`
gets one new `font-family` declaration on the existing shared module-style rule, plus one new
divider rule for the 4 sections. `home/dot_local/bin/executable_archfrican-weather`'s icon table —
discovered broken (15 of 16 glyphs are empty strings, not just a style mismatch) — gets fully
restored. Two more scripts (`archfrican-net-status`, `archfrican-privacy-indicator`) get their
plain-text `●` status dot converted to the same Nerd Font glyph used everywhere else.

**Tech Stack:** JSONC (Waybar config), CSS (GTK), Bash (`set -euo pipefail`/`set -uo pipefail`),
Python 3 (used only as a one-shot, throwaway rewrite tool during implementation — never added as a
runtime dependency of any script).

## Global Constraints

- Full spec: `docs/superpowers/specs/2026-07-06-waybar-minimalist-groups-design.md`.
- **Never type a Nerd Font icon glyph literally into a file.** Every codepoint used in this plan
  (Private Use Area / supplementary plane) has been proven to silently vanish (becomes an empty
  string) when pasted directly as a literal character — confirmed with `hexdump` while writing the
  spec, and almost certainly how `archfrican-weather`'s icon table broke in the first place. Every
  step in this plan that inserts a glyph does so via a Python rewrite script using `"\UXXXXXXXX"`
  string escapes (decoded by the Python interpreter at rewrite time, never typed as a raw
  character), or — for the two bash scripts — a `$'\xHH\xHH\xHH'` byte escape assigned to a named
  variable, matching the exact convention already established in
  `home/dot_local/bin/executable_archfrican-caffeine`. Ordinary BMP characters (`●` U+25CF, `—`
  U+2014) are NOT affected by this and may be typed/matched literally.
- **Every glyph insertion is verified by comparing `hex(ord(char))` against the expected codepoint
  after the write — never by eyeballing the file.** This is the same method used to write the spec.
- Every rewrite script asserts its anchor text matches **exactly once** (`text.count(old) == 1`)
  before replacing — if the count is ever not 1, STOP and re-read the file; something changed
  concurrently (this repo has had concurrent Claude sessions touching it before).
- No module is deleted and no information is removed from what's visible today — the change is
  purely visual grouping + font unification (the one exception, explicitly approved in the spec: the
  inline `{volume}%` moves from the bar into `pulseaudio`'s tooltip).
- `home/dot_local/bin/executable_archfrican-wallpaper`, `-wallpaper-restore`, and
  `home/dot_config/waybar/colors.css` are NOT touched by this plan.
- No automated test harness exists for `waybar/` JSONC or CSS in this repo — validation is static
  (JSON-validity after stripping `//` comments, Python structural checks, `bash -n` for the two
  shell scripts) plus a manually-run live check documented in Task 5 (restarting waybar is a
  live-system action; the plan documents the steps, it does not run them for you).

---

### Task 1: Fix `archfrican-weather`'s broken icon table

**Files:**
- Modify: `home/dot_local/bin/executable_archfrican-weather:54-61`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: nothing other tasks depend on — this is an independent bug fix incidentally caught
  while scoping the icon-font-unification work, folded in here because Task 2 area of concern
  (icon consistency) already touches this exact file's icon table.

- [ ] **Step 1: Confirm the current exact content**

Run: `sed -n '54,61p' home/dot_local/bin/executable_archfrican-weather`

Expected (the dict currently has 15 empty-string values and one Material Design Icons glyph for
`overcast` — do not trust how this renders in your terminal; the next step proves it
programmatically):
```
ICONS = {
    "sunny": "", "clear": "", "partly": "",
    "cloud": "", "overcast": "X",
    "rain": "", "drizzle": "", "shower": "",
    "snow": "", "blizzard": "", "sleet": "",
    "thunder": "", "lightning": "",
    "mist": "", "fog": "", "haze": "",
}
```
(`X` above stands in for whatever your terminal shows for the "overcast" glyph — do not
transcribe it by hand.)

- [ ] **Step 2: Write the failing check (proves today's file is broken)**

Run:
```bash
sed -n '54,61p' home/dot_local/bin/executable_archfrican-weather | python3 -c "
import sys
ns = {}
exec(sys.stdin.read(), ns)
icons = ns['ICONS']
assert len(icons) == 16, f'expected 16 keys, got {len(icons)}'
empty = [k for k, v in icons.items() if v == '']
print(f'{len(empty)} of 16 keys are empty: {empty}')
"
```
Expected: `15 of 16 keys are empty: ['sunny', 'clear', 'partly', 'cloud', 'rain', 'drizzle',
'shower', 'snow', 'blizzard', 'sleet', 'thunder', 'lightning', 'mist', 'fog', 'haze']` — confirms
the bug before touching anything.

- [ ] **Step 3: Rewrite the ICONS block via a Python script (never by hand-typing the glyphs)**

Run:
```bash
python3 <<'PYEOF'
path = "home/dot_local/bin/executable_archfrican-weather"
text = open(path, encoding="utf-8").read()

old_block = (
    '    "sunny": "", "clear": "", "partly": "",\n'
    '    "cloud": "", "overcast": "\U000F0590",\n'
    '    "rain": "", "drizzle": "", "shower": "",\n'
    '    "snow": "", "blizzard": "", "sleet": "",\n'
    '    "thunder": "", "lightning": "",\n'
    '    "mist": "", "fog": "", "haze": "",\n'
)
new_block = (
    '    "sunny": "\U0000E30D", "clear": "\U0000E32B", "partly": "\U0000E302",\n'
    '    "cloud": "\U0000E33D", "overcast": "\U0000E312",\n'
    '    "rain": "\U0000E318", "drizzle": "\U0000E31B", "shower": "\U0000E319",\n'
    '    "snow": "\U0000E31A", "blizzard": "\U0000E35E", "sleet": "\U0000E3AD",\n'
    '    "thunder": "\U0000E31D", "lightning": "\U0000E315",\n'
    '    "mist": "\U0000E313", "fog": "\U0000E313", "haze": "\U0000E3AE",\n'
)
count = text.count(old_block)
assert count == 1, f"expected exactly 1 match, found {count} — STOP, re-read the file"
text = text.replace(old_block, new_block)
open(path, "w", encoding="utf-8").write(text)
print("rewrote ICONS block OK")
PYEOF
```
Expected: `rewrote ICONS block OK`.

`\U000F0590` is the exact codepoint of the existing (Material Design Icons) "overcast" glyph
this replaces; all 16 new glyphs are Weather Icons subset, confirmed present in
`JetBrainsMonoNerdFont-Regular.ttf` via `fontTools` while writing the spec:

| clave | codepoint | clave | codepoint |
|---|---|---|---|
| sunny | U+E30D | thunder | U+E31D |
| clear | U+E32B | lightning | U+E315 |
| partly | U+E302 | mist | U+E313 |
| cloud | U+E33D | fog | U+E313 |
| overcast | U+E312 | haze | U+E3AE |
| rain | U+E318 | drizzle | U+E31B |
| snow | U+E31A | shower | U+E319 |
| blizzard | U+E35E | sleet | U+E3AD |

- [ ] **Step 4: Run the passing check (proves the fix)**

Run:
```bash
sed -n '54,61p' home/dot_local/bin/executable_archfrican-weather | python3 -c "
import sys
ns = {}
exec(sys.stdin.read(), ns)
icons = ns['ICONS']
assert len(icons) == 16, f'expected 16 keys, got {len(icons)}'
expected = {
    'sunny': 0xE30D, 'clear': 0xE32B, 'partly': 0xE302,
    'cloud': 0xE33D, 'overcast': 0xE312,
    'rain': 0xE318, 'drizzle': 0xE31B, 'shower': 0xE319,
    'snow': 0xE31A, 'blizzard': 0xE35E, 'sleet': 0xE3AD,
    'thunder': 0xE31D, 'lightning': 0xE315,
    'mist': 0xE313, 'fog': 0xE313, 'haze': 0xE3AE,
}
for key, cp in expected.items():
    glyph = icons[key]
    assert len(glyph) == 1, f'{key}: expected 1 char, got {glyph!r}'
    assert ord(glyph) == cp, f'{key}: expected U+{cp:04X}, got U+{ord(glyph):04X}'
print('OK: all 16 weather icons decode to the expected codepoint')
"
```
Expected: `OK: all 16 weather icons decode to the expected codepoint`.

- [ ] **Step 5: Verify syntax**

Run: `bash -n home/dot_local/bin/executable_archfrican-weather`
Expected: no output, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add home/dot_local/bin/executable_archfrican-weather
git commit -m "$(cat <<'EOF'
fix(weather): restore the 15 missing waybar weather icons

hexdump confirmed every ICONS entry except "overcast" was a bare
empty string -- the weather pill never showed an icon for any
condition except exactly "overcast". Restores all 16 from the
Weather Icons Nerd Font subset (verified against the real installed
font with fontTools, not typed by hand -- literal Private-Use-Area
glyphs silently vanish when pasted into a file, which is almost
certainly how this broke originally).
EOF
)"
```

---

### Task 2: Unify the 3 status-dot indicators to one Nerd Font glyph

**Files:**
- Modify: `home/dot_config/waybar/config.jsonc:89-103` (`custom/notification`)
- Modify: `home/dot_local/bin/executable_archfrican-net-status`
- Modify: `home/dot_local/bin/executable_archfrican-privacy-indicator`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: nothing later tasks depend on (Task 3/4 touch different parts of the same files and
  don't reference this glyph).

- [ ] **Step 1: Confirm current exact content of the three spots**

Run:
```bash
sed -n '89,103p' home/dot_config/waybar/config.jsonc
grep -n 'set -uo pipefail\|printf.*"text"' home/dot_local/bin/executable_archfrican-net-status
grep -n 'set -uo pipefail\|printf.*"text"' home/dot_local/bin/executable_archfrican-privacy-indicator
```
Expected: the `custom/notification` block with 4 `"●"` occurrences (config.jsonc), and each bash
script's `set -uo pipefail` line followed later by `printf` calls containing `"●"` — if the grep
output looks different from what Step 2/3 below expect to replace, STOP and re-read the whole file
before proceeding.

- [ ] **Step 2: Rewrite `config.jsonc`'s `custom/notification` block**

Run:
```bash
python3 <<'PYEOF'
path = "home/dot_config/waybar/config.jsonc"
text = open(path, encoding="utf-8").read()

old = (
    '      "notification": "●", "none": "",\n'
    '      "dnd-notification": "●", "dnd-none": "",\n'
    '      "inhibited-notification": "●", "inhibited-none": "",\n'
    '      "dnd-inhibited-notification": "●", "dnd-inhibited-none": ""\n'
)
new = (
    '      "notification": "\U0000F111", "none": "",\n'
    '      "dnd-notification": "\U0000F111", "dnd-none": "",\n'
    '      "inhibited-notification": "\U0000F111", "inhibited-none": "",\n'
    '      "dnd-inhibited-notification": "\U0000F111", "dnd-inhibited-none": ""\n'
)
count = text.count(old)
assert count == 1, f"expected exactly 1 match, found {count} — STOP, re-read the file"
text = text.replace(old, new)
open(path, "w", encoding="utf-8").write(text)
print("rewrote custom/notification format-icons OK")
PYEOF
```
Expected: `rewrote custom/notification format-icons OK`. (U+F111 is `fa-circle`, Font Awesome
subset, confirmed present in `JetBrainsMonoNerdFont-Regular.ttf`.)

- [ ] **Step 3: Rewrite `archfrican-net-status` (adds a `DOT` var, extends 4 printf calls)**

Run:
```bash
python3 <<'PYEOF'
path = "home/dot_local/bin/executable_archfrican-net-status"
text = open(path, encoding="utf-8").read()

old_anchor = 'set -uo pipefail\n'
new_anchor = (
    'set -uo pipefail\n'
    "DOT=$'\\xef\\x84\\x91'   # nf-fa-circle  U+F111 — same glyph unifying every status dot in the bar\n"
)
assert text.count(old_anchor) == 1, "STOP: set -uo pipefail line not found or not unique"
text = text.replace(old_anchor, new_anchor, 1)

replacements = [
    ('printf \'{"text":"●","class":"offline","tooltip":"Sin conexión a Internet"}\\n\'',
     'printf \'{"text":"%s","class":"offline","tooltip":"Sin conexión a Internet"}\\n\' "$DOT"'),
    ('printf \'{"text":"●","class":"unstable","tooltip":"Conexión inestable — %s%% de pérdida%s"}\\n\' "$loss" "${avg:+, ${avg} ms}"',
     'printf \'{"text":"%s","class":"unstable","tooltip":"Conexión inestable — %s%% de pérdida%s"}\\n\' "$DOT" "$loss" "${avg:+, ${avg} ms}"'),
    ('printf \'{"text":"●","class":"unstable","tooltip":"Conexión lenta — %s ms"}\\n\' "$avg"',
     'printf \'{"text":"%s","class":"unstable","tooltip":"Conexión lenta — %s ms"}\\n\' "$DOT" "$avg"'),
    ('printf \'{"text":"●","class":"online","tooltip":"Internet estable%s"}\\n\' "${avg:+ — ${avg} ms}"',
     'printf \'{"text":"%s","class":"online","tooltip":"Internet estable%s"}\\n\' "$DOT" "${avg:+ — ${avg} ms}"'),
]
for old, new in replacements:
    c = text.count(old)
    assert c == 1, f"expected 1 match, found {c} — STOP, re-read the file: {old!r}"
    text = text.replace(old, new)

open(path, "w", encoding="utf-8").write(text)
print("rewrote archfrican-net-status OK")
PYEOF
```
Expected: `rewrote archfrican-net-status OK`.

- [ ] **Step 4: Rewrite `archfrican-privacy-indicator` (same `DOT` pattern)**

Run:
```bash
python3 <<'PYEOF'
path = "home/dot_local/bin/executable_archfrican-privacy-indicator"
text = open(path, encoding="utf-8").read()

old_anchor = 'set -uo pipefail\n'
new_anchor = (
    'set -uo pipefail\n'
    "DOT=$'\\xef\\x84\\x91'   # nf-fa-circle  U+F111 — same glyph unifying every status dot in the bar\n"
)
assert text.count(old_anchor) == 1, "STOP: set -uo pipefail line not found or not unique"
text = text.replace(old_anchor, new_anchor, 1)

old = 'printf \'{"text":"●","class":"privacy","tooltip":"%s en uso"}\\n\' "$parts"'
new = 'printf \'{"text":"%s","class":"privacy","tooltip":"%s en uso"}\\n\' "$DOT" "$parts"'
c = text.count(old)
assert c == 1, f"expected 1 match, found {c} — STOP, re-read the file"
text = text.replace(old, new)

open(path, "w", encoding="utf-8").write(text)
print("rewrote archfrican-privacy-indicator OK")
PYEOF
```
Expected: `rewrote archfrican-privacy-indicator OK`.

- [ ] **Step 5: Verify syntax on both scripts**

Run:
```bash
bash -n home/dot_local/bin/executable_archfrican-net-status && echo "OK: net-status"
bash -n home/dot_local/bin/executable_archfrican-privacy-indicator && echo "OK: privacy-indicator"
```
Expected: `OK: net-status` and `OK: privacy-indicator`.

- [ ] **Step 6: Verify the dot decodes correctly end-to-end (net-status)**

Run:
```bash
bash -c '
DOT=$'"'"'\xef\x84\x91'"'"'
printf "{\"text\":\"%s\"}" "$DOT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert ord(d[\"text\"]) == 0xF111, hex(ord(d[\"text\"]))
print(\"OK: dot decodes to U+F111\")
"
'
```
Expected: `OK: dot decodes to U+F111`.

- [ ] **Step 7: Confirm JSON validity of config.jsonc**

Run: `grep -v '^\s*//' home/dot_config/waybar/config.jsonc | jq . > /dev/null && echo "JSON valid"`
Expected: `JSON valid`.

- [ ] **Step 8: Commit**

```bash
git add home/dot_config/waybar/config.jsonc \
        home/dot_local/bin/executable_archfrican-net-status \
        home/dot_local/bin/executable_archfrican-privacy-indicator
git commit -m "$(cat <<'EOF'
feat(waybar): unify the 3 status dots to one Nerd Font glyph

Connectivity, privacy, and notification dots used a plain Unicode
"." chosen on purpose back when depending on Nerd Font wasn't safe
to assume. Nerd Font (ttf-jetbrains-mono-nerd) is now a hard
dependency of the theme, so that reasoning no longer applies -- all
three switch to fa-circle (U+F111), the same glyph family already
used everywhere else in the bar.
EOF
)"
```

---

### Task 3: Restructure `modules-right` into groups + simplify the volume module

**Files:**
- Modify: `home/dot_config/waybar/config.jsonc:12-18` (`modules-right` array)
- Modify: `home/dot_config/waybar/config.jsonc:125-129` (`pulseaudio` block)

**Interfaces:**
- Consumes: nothing from Tasks 1-2 (different sections of the same file, non-overlapping text).
- Produces: the CSS ids `#system`, `#connectivity`, `#status` that Task 4 styles. Task 4's
  implementer must NOT run before this task is committed — the ids don't exist until this task
  lands.

- [ ] **Step 1: Confirm current exact content of both spots**

Run:
```bash
sed -n '12,18p' home/dot_config/waybar/config.jsonc
sed -n '125,129p' home/dot_config/waybar/config.jsonc
```
Expected:
```
  "modules-right": [
    "custom/privacy",
    "pulseaudio", "bluetooth", "custom/connectivity", "network",
    "cpu", "memory", "disk",
    "power-profiles-daemon", "battery",
    "custom/caffeine", "custom/health", "custom/notification", "tray"
  ],
```
and
```
  "pulseaudio": {
    "format": "{icon}  {volume}%",
    "format-icons": { "default": ["", "", ""] },
    "on-click": "pavucontrol"
  },
```
(the 3 icons in `format-icons` render as glyphs in your terminal — Step 2 matches them by
codepoint, not by hand-transcription, so it's fine if they don't display correctly for you.) If
either block looks different, STOP and re-read the whole file — Task 2 must already be committed
before this step (it touches `custom/notification`, a different block, but confirms the file is in
the expected post-Task-2 state).

- [ ] **Step 2: Rewrite both blocks via a Python script**

Run:
```bash
python3 <<'PYEOF'
path = "home/dot_config/waybar/config.jsonc"
text = open(path, encoding="utf-8").read()

old_modules = (
    '  "modules-right": [\n'
    '    "custom/privacy",\n'
    '    "pulseaudio", "bluetooth", "custom/connectivity", "network",\n'
    '    "cpu", "memory", "disk",\n'
    '    "power-profiles-daemon", "battery",\n'
    '    "custom/caffeine", "custom/health", "custom/notification", "tray"\n'
    '  ],\n'
)
new_modules = (
    '  "modules-right": ["pulseaudio", "group/system", "group/connectivity", "group/status"],\n'
    '\n'
    '  "group/system": {\n'
    '    "orientation": "horizontal",\n'
    '    "modules": ["cpu", "memory", "disk", "power-profiles-daemon", "battery"]\n'
    '  },\n'
    '  "group/connectivity": {\n'
    '    "orientation": "horizontal",\n'
    '    "modules": ["network", "bluetooth", "custom/connectivity"]\n'
    '  },\n'
    '  "group/status": {\n'
    '    "orientation": "horizontal",\n'
    '    "modules": ["custom/health", "custom/notification", "custom/caffeine", "custom/privacy", "tray"]\n'
    '  },\n'
)
c1 = text.count(old_modules)
assert c1 == 1, f"expected 1 match, found {c1} — STOP, re-read the file"
text = text.replace(old_modules, new_modules)

old_pulse = (
    '  "pulseaudio": {\n'
    '    "format": "{icon}  {volume}%",\n'
    '    "format-icons": { "default": ["\U0000F026", "\U0000F027", "\U0000F028"] },\n'
    '    "on-click": "pavucontrol"\n'
    '  },\n'
)
new_pulse = (
    '  "pulseaudio": {\n'
    '    "format": "{icon}",\n'
    '    "format-muted": "\U0000EEE8",\n'
    '    "format-icons": { "default": ["\U0000F026", "\U0000F027", "\U0000F028"] },\n'
    '    "tooltip-format": "{volume}% — {desc}",\n'
    '    "on-click": "pavucontrol"\n'
    '  },\n'
)
c2 = text.count(old_pulse)
assert c2 == 1, f"expected 1 match, found {c2} — STOP, re-read the file"
text = text.replace(old_pulse, new_pulse)

open(path, "w", encoding="utf-8").write(text)
print("rewrote modules-right + pulseaudio OK")
PYEOF
```
Expected: `rewrote modules-right + pulseaudio OK`.

`group/connectivity` (not `group/network`) is deliberate: Waybar assigns a module named
`"group/<name>"` the CSS id `#<name>` (no `group-` prefix — confirmed against the official Waybar
wiki and [Alexays/waybar#4378](https://github.com/Alexays/waybar/issues/4378)). `group/network`
would collide with the existing standalone `network` module's own `#network` id.

`\U0000EEE8` is `fa-volume_xmark` — a distinct Font Awesome "muted speaker" glyph, NOT the same as
the existing `\U0000F026` already used for the lowest non-zero volume level in `format-icons`
(don't touch that array — it's correct as-is and this task doesn't change it).

- [ ] **Step 3: Confirm JSON validity**

Run: `grep -v '^\s*//' home/dot_config/waybar/config.jsonc | jq . > /dev/null && echo "JSON valid"`
Expected: `JSON valid`.

- [ ] **Step 4: Verify the full structure programmatically**

Run:
```bash
python3 -c "
import json
text = open('home/dot_config/waybar/config.jsonc', encoding='utf-8').read()
stripped = '\n'.join(l for l in text.split('\n') if not l.strip().startswith('//'))
d = json.loads(stripped)
assert d['modules-right'] == ['pulseaudio', 'group/system', 'group/connectivity', 'group/status'], d['modules-right']
assert d['group/system']['modules'] == ['cpu', 'memory', 'disk', 'power-profiles-daemon', 'battery']
assert d['group/connectivity']['modules'] == ['network', 'bluetooth', 'custom/connectivity']
assert d['group/status']['modules'] == ['custom/health', 'custom/notification', 'custom/caffeine', 'custom/privacy', 'tray']
assert d['pulseaudio']['format'] == '{icon}'
assert ord(d['pulseaudio']['format-muted']) == 0xEEE8, hex(ord(d['pulseaudio']['format-muted']))
assert d['pulseaudio']['tooltip-format'] == '{volume}% — {desc}'
print('OK: modules-right, 3 groups, and pulseaudio all match the plan exactly')
"
```
Expected: `OK: modules-right, 3 groups, and pulseaudio all match the plan exactly`.

- [ ] **Step 5: Commit**

```bash
git add home/dot_config/waybar/config.jsonc
git commit -m "$(cat <<'EOF'
feat(waybar): group the right side into system/connectivity/status

modules-right shrinks from 14 flat entries to 4: pulseaudio plus
three native Waybar group/* modules, each wrapping the existing
modules with zero change to their own config. Volume drops its
inline {volume}% for a tooltip (same pattern disk already uses),
since it's checked far less often than the rest and doesn't need to
occupy bar space at rest -- adds a distinct format-muted icon since
that's now the only at-a-glance mute signal.
EOF
)"
```

---

### Task 4: Style the new groups (font unification + section dividers)

**Files:**
- Modify: `home/dot_config/waybar/style.css:33-44`

**Interfaces:**
- Consumes: the CSS ids `#system`, `#connectivity`, `#status` produced by Task 3 — this task must
  run after Task 3 is committed.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Confirm current exact content**

Run: `sed -n '32,44p' home/dot_config/waybar/style.css`

Expected:
```
/* every module sits flush inside its island */
#workspaces button,
#window, #clock,
#custom-privacy, #pulseaudio, #bluetooth, #network,
#cpu, #memory, #disk, #power-profiles-daemon, #battery,
#custom-caffeine, #custom-weather, #custom-connectivity,
#custom-health, #custom-notification, #tray {
  padding: 2px 7px;
  margin: 3px 1px;
  color: @fg;
  background: transparent;
  border-radius: 11px;
}
```
If this doesn't match, STOP and re-read the whole file.

- [ ] **Step 2: Add the font-family declaration and the divider rule**

Edit `home/dot_config/waybar/style.css`, replacing:
```css
#workspaces button,
#window, #clock,
#custom-privacy, #pulseaudio, #bluetooth, #network,
#cpu, #memory, #disk, #power-profiles-daemon, #battery,
#custom-caffeine, #custom-weather, #custom-connectivity,
#custom-health, #custom-notification, #tray {
  padding: 2px 7px;
  margin: 3px 1px;
  color: @fg;
  background: transparent;
  border-radius: 11px;
}
```
with:
```css
#workspaces button,
#window, #clock,
#custom-privacy, #pulseaudio, #bluetooth, #network,
#cpu, #memory, #disk, #power-profiles-daemon, #battery,
#custom-caffeine, #custom-weather, #custom-connectivity,
#custom-health, #custom-notification, #tray {
  padding: 2px 7px;
  margin: 3px 1px;
  color: @fg;
  background: transparent;
  border-radius: 11px;
  font-family: "JetBrainsMono Nerd Font";
}

/* right island: divider between volume | system | connectivity | status */
#pulseaudio, #system, #connectivity {
  border-right: 1px solid alpha(@fg_dim, 0.20);
  padding-right: 10px;
  margin-right: 2px;
}
```
This is pure ASCII (no glyphs involved) — a direct file edit is safe here, unlike Tasks 1-3.

`#system`/`#connectivity`/`#status` need no other new rules: each existing per-module id (`#cpu`,
`#network`, etc.) keeps its own padding/margin/color/hover rules from the block above and from the
`:hover` block further down — those are untouched, and still apply because a module's own CSS id
doesn't change when it's nested inside a `group`. `#status` deliberately does NOT get the divider
(it's the last section, flush against the island's own right edge).

- [ ] **Step 3: Confirm the edit landed correctly**

Run:
```bash
grep -n 'font-family: "JetBrainsMono Nerd Font";' home/dot_config/waybar/style.css
grep -n '#pulseaudio, #system, #connectivity' home/dot_config/waybar/style.css
```
Expected: one match for each grep, both inside the block you just edited.

- [ ] **Step 4: Commit**

```bash
git add home/dot_config/waybar/style.css
git commit -m "$(cat <<'EOF'
feat(waybar): unify icon font + divide the 4 right-side sections

font-family: "JetBrainsMono Nerd Font" is now explicit on every
module (previously relied on font-family fallback, which happened
to already resolve every glyph to this font -- explicit now so it
can never silently fall through to Inter/sans-serif). Adds a thin
border-right divider -- the same value already used between the
weather pill and the clock -- to #pulseaudio, #system, and
#connectivity, visually separating the 4 right-side sections
without turning them into separate floating islands.
EOF
)"
```

---

### Task 5: End-to-end static verification + live-verification instructions

**Files:** none modified — this task only runs checks and documents the manual live-verification
steps for the user (restarting waybar affects the live session, which this plan does not do
automatically).

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: nothing further downstream.

- [ ] **Step 1: Full static re-check of every file this plan touched**

Run:
```bash
for f in home/dot_local/bin/executable_archfrican-weather \
         home/dot_local/bin/executable_archfrican-net-status \
         home/dot_local/bin/executable_archfrican-privacy-indicator; do
  bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"
done
grep -v '^\s*//' home/dot_config/waybar/config.jsonc | jq . > /dev/null && echo "OK: config.jsonc is valid JSON"
```
Expected: `OK:` for all four checks.

- [ ] **Step 2: Full structural re-verification of config.jsonc**

Run:
```bash
python3 -c "
import json
text = open('home/dot_config/waybar/config.jsonc', encoding='utf-8').read()
stripped = '\n'.join(l for l in text.split('\n') if not l.strip().startswith('//'))
d = json.loads(stripped)
assert d['modules-right'] == ['pulseaudio', 'group/system', 'group/connectivity', 'group/status']
assert d['group/system']['modules'] == ['cpu', 'memory', 'disk', 'power-profiles-daemon', 'battery']
assert d['group/connectivity']['modules'] == ['network', 'bluetooth', 'custom/connectivity']
assert d['group/status']['modules'] == ['custom/health', 'custom/notification', 'custom/caffeine', 'custom/privacy', 'tray']
assert d['pulseaudio']['format'] == '{icon}'
assert ord(d['pulseaudio']['format-muted']) == 0xEEE8
assert ord(d['custom/notification']['format-icons']['notification']) == 0xF111
print('OK: config.jsonc structure matches the plan')
"
```
Expected: `OK: config.jsonc structure matches the plan`.

- [ ] **Step 3: Full re-verification of archfrican-weather's icon table**

Run:
```bash
sed -n '54,61p' home/dot_local/bin/executable_archfrican-weather | python3 -c "
import sys
ns = {}
exec(sys.stdin.read(), ns)
icons = ns['ICONS']
assert len(icons) == 16
assert all(len(v) == 1 for v in icons.values()), 'some icon is still empty or multi-char'
print('OK: all 16 weather icons have exactly one glyph')
"
```
Expected: `OK: all 16 weather icons have exactly one glyph`.

- [ ] **Step 4: Confirm style.css changes are present**

Run:
```bash
grep -c 'font-family: "JetBrainsMono Nerd Font";' home/dot_config/waybar/style.css
grep -c '#pulseaudio, #system, #connectivity' home/dot_config/waybar/style.css
```
Expected: `1` for both.

- [ ] **Step 5: Re-run the existing test suites to confirm nothing regressed**

Run:
```bash
bash tests/unit/manifest.sh | tail -3
bash tests/unit/detect-gpu.sh | tail -3
```
Expected: `manifest unit test: 9 passed, 0 failed` and `detect-gpu unit test: 13 passed, 0
failed` (this plan doesn't touch either file, so these numbers should be unchanged — if they
differ, something else changed concurrently; investigate before continuing).

- [ ] **Step 6: Document the live-verification steps (for the user to run themselves)**

Add nothing to a file — this step is just running the following manually, since it restarts the
user's actual running waybar:

```bash
pkill waybar   # systemd's waybar.service (already in place) relaunches it automatically
```
Then, in the niri session:
- Confirm the right side now shows 4 visually distinct sections (volume · system · connectivity ·
  status) separated by a thin divider, inside one continuous island — not 4 separate floating
  pills, and not still one undifferentiated row of 14 icons.
- Confirm the volume icon shows NO percentage inline; hovering over it shows a tooltip with the
  `%` and active output device; muting shows a distinct icon from the normal low/medium/high ones.
- Confirm every glyph (battery, network, bluetooth, cpu, memory, disk, power profile, caffeine,
  health, weather, and the 3 status dots) looks like the same visual family — no "tofu" box (glyph
  missing from the font) and no glyph that visually looks like it's from a different icon set.
- Confirm the weather pill (center island) now shows an icon for whatever today's actual
  condition is, not just when it happens to be "overcast".
- Confirm nothing that was visible before is now missing (everything either still shows inline or
  is one hover/click away, per the spec).

- [ ] **Step 7: No commit for this task** (verification-only; nothing to add to git).
