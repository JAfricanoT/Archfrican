# App Cohesion — Tier B (apps that ignore GTK/Qt)

The other half of [DESIGN-LANGUAGE.md](DESIGN-LANGUAGE.md). Most apps inherit the identity for free
through the GTK/Qt/fontconfig/cursor render path; a few ignore all of that. This is how *those* still
end up wearing the Archfrican teal — through the opt-in `archfrican-cohesion` layer.

## Two tiers

- **Tier A — honour GTK / Qt / fontconfig / cursor.** GTK apps, Qt apps, the terminal, the bar, the
  launcher. Themed **always-on** by `bin/theme-switch`'s render path; nothing to enable. Not governed
  here.
- **Tier B — ignore desktop settings entirely.** VS Code (Electron) and Chromium **web-apps** paint
  their own chrome. They need an *explicit* injection of the tokens, which is what `archfrican-cohesion`
  does.

## The model — on by default, remembered, reversible

```
archfrican-cohesion on | off | status | apply
```

- **ON by default** — homogeneity is the point. `modules/40-theming.sh` seeds the flag at
  install/converge, *only if no choice has been made yet*.
- Two flags under `~/.config/archfrican/`: `cohesion-on` (enabled) and `cohesion-off-chosen` (a manual
  `off` is **remembered**, so converge re-runs never silently re-enable it).
- Toggle interactively: `archfrican-actions` → **"Cohesión de apps (alternar)"**.
- **Nothing explodes.** VS Code settings are backed up before the first change and `off` restores the
  backup exactly. `apply` only acts when enabled.

## VS Code

| Step | What happens |
|---|---|
| render | `theme-switch` renders `templates/vscode.colors.json` → `~/.config/archfrican/cohesion/vscode.colors.json` (**staging**, always, every theme switch) |
| apply | `archfrican-cohesion apply` deep-merges staging into `~/.config/Code/User/settings.json` via `jq -s '.[0] * .[1]'` — your settings keep their structure; only the ADL keys are added/overwritten |
| backup | one-time `settings.json.archfrican.bak` before the first write; `off` moves it back |
| no-op | VS Code never launched, `jq` missing, or `settings.json` has JSONC comments `jq` can't parse → left untouched |

What it sets: accent on focus border, buttons, badges, links, active tab/activity borders
(`${ACCENT}` / `${ACCENT_FG}`), and the editor + integrated-terminal font (`${FONT_MONO}`).

## Chromium web-apps

| Step | What happens |
|---|---|
| render | `theme-switch` renders `templates/webapp.css` → `~/.local/share/archfrican-webapps-ext/theme.css` |
| inject | `manifest.json` (MV3 unpacked extension) injects `theme.css` into `<all_urls>` at `document_start` |
| launch | `archfrican-webapp` adds `--load-extension=<ext>` when `manifest.json` exists — **best-effort**: the web-app still launches if the extension is absent or ignored |

The web-app skin is deliberately **neutral** — chrome-level only (`accent-color`, `::selection`,
scrollbar via `${ACCENT}` / `${ACCENT_FG}` / `${BG_DIM}` / `${RADIUS_SM}`). No per-site restyling, so it
degrades to "slightly themed" on any page and never breaks one.

## How it rides the theme-switch flow

`theme-switch` **always renders** both Tier-B outputs (the VS Code staging file + the web-app
`theme.css`), regardless of the flag, so the artifacts are always current. It then calls
`archfrican-cohesion apply` **only if `cohesion-on` exists** — so switching theme propagates into VS
Code live, and web-apps pick it up on their next launch. The generated outputs live in
`home/.chezmoiignore` (theme-switch is their sole writer); the hand-written `manifest.json` is **not**
ignored, so chezmoi deploys it.

## Add a new Tier-B app

1. Stage a token fragment in `templates/<app>.<ext>` referencing `${TOKEN}`s (theme-switch
   auto-discovers them — see the DESIGN-LANGUAGE recipe).
2. Add a `render <fragment> <staging-path>` line to `bin/theme-switch`'s Tier-B section.
3. Teach `archfrican-cohesion` to inject the staged fragment into the app and to **restore** it on
   `off`, with a **one-time backup** before the first write.
4. Gate the injection on the `cohesion-on` flag; add the generated output to `home/.chezmoiignore`.

## Honest limits

- Injection only reaches apps that expose a hook — VS Code's `colorCustomizations`, Chromium's
  `--load-extension`. An app with neither can't be Tier-B-themed.
- The web-app skin is intentionally neutral; it does not (and should not) restyle individual sites.
- The VS Code merge needs `jq` and parseable JSON; a settings file with heavy JSONC comments is left
  alone rather than risk corrupting it.
- Not hardware-validated yet; every step degrades gracefully if a tool or path is missing.
