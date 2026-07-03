# Governance / Gobernanza

> 🇬🇧 English first · 🇪🇸 Español a continuación.

## English

### Model
Archfrican is **maintainer-led (BDFL)**. The maintainer is **[@JAfricanoT](https://github.com/JAfricanoT)**.
Decisions are made by **lazy consensus** on issues/PRs; if there's no objection, a change moves forward. On
disagreement, the maintainer arbitrates. Only the maintainer merges to `main`.

### Merge requirements (every PR)
- **CI is green** — all gates pass (see [CONTRIBUTING.md](CONTRIBUTING.md) / `.github/workflows/ci.yml`:
  `shellcheck`, `bashn`, `firewall-ruleset`, `grub-helper`, `iso-safety-gate`, `migrations-idempotent`,
  `prune-safety`, `cachyos-trust`, `theme-switch-smoke`, `sddm-theme`, `pkg-resolution`, `fido2-selfcheck`).
- **Conventional Commit** title; **no AI attribution** anywhere git-visible.
- Stays within scope — see the [VISION.md](VISION.md) non-goals. Out-of-scope PRs are closed with a pointer.

### Special rule — security / disk / boot / auth changes
Changes touching **disk partitioning, the bootloader, encryption/LUKS, PAM/sudo/FIDO2, the firewall, or the
supply chain** carry the highest blast radius and get extra scrutiny before merge:
1. **Adversarial review** — the change is reviewed against the audit findings in
   [docs/audit/01-security-supply-chain.md](docs/audit/01-security-supply-chain.md) and
   [docs/audit/02-data-integrity-ops.md](docs/audit/02-data-integrity-ops.md): a reviewer actively tries to
   break it, not just read it.
2. **VM validation** — disk/boot changes are validated on a VM per
   [docs/STAGE2-VALIDATION.md](docs/STAGE2-VALIDATION.md) (not the general docs/VALIDATION.md) before they
   ship enabled.
3. **Safety gates held** — none of these may be weakened by the PR: `ARCHFRICAN_ISO_ARMED` defaults to `0`
   (the ISO installer defaults to a dry-run preview), both disk gates (`confirm_wipe` retype + the arming
   opt-in), the FIDO2
   non-exclusive/no-lockout invariant (pam-u2f ≥ 1.3.1), the named-table-never-`flush ruleset` firewall,
   the fail-closed CachyOS signing-key fingerprint pin, `ARCHFRICAN_DEEPCLEAN_ARMED` defaults to `0` (the
   deep-clean wipe defaults to a dry-run preview, same pattern as `ARCHFRICAN_ISO_ARMED`), the subvolume
   delete allowlist (`DEEPCLEAN_DELETE_SUBVOLS`) staying a fixed literal — never computed from a live `btrfs
   subvolume list` — with `@home` never appearing in it, and deep-clean only ever operating at the
   btrfs-subvolume level, never calling a full-disk reformat verb (`mkfs.btrfs`, `cryptsetup luksFormat`,
   `wipefs`, `sgdisk`). The CI `iso-safety-gate` + `firewall-ruleset` + `deepclean-safety-gate` jobs enforce
   several of these mechanically.

### Releases & versioning
Semantic-ish tags (`vMAJOR.MINOR`). The commit history is the changelog until the first tagged release;
after that, a `CHANGELOG.md` (Keep a Changelog) is generated from the Conventional-Commit log. Release tags
are signed (`git tag -s`) once tag-signing is set up.

### Becoming a maintainer
Sustained, high-quality contributions + good judgment on the safety rules above. The maintainer invites new
maintainers; there is no fixed quota.

## Español

### Modelo
Archfrican es **liderado por el mantenedor (BDFL)**. El mantenedor es
**[@JAfricanoT](https://github.com/JAfricanoT)**. Las decisiones se toman por **consenso perezoso** en
issues/PRs; si no hay objeción, el cambio avanza. Ante desacuerdo, el mantenedor arbitra. Solo el mantenedor
hace merge a `main`.

### Requisitos de merge (todo PR)
- **CI en verde** — todas las verificaciones pasan (ver [CONTRIBUTING.md](CONTRIBUTING.md)).
- Título en **Conventional Commit**; **sin atribución de IA** en nada visible en git.
- Dentro del alcance — ver los no-objetivos de [VISION.md](VISION.md). Los PR fuera de alcance se cierran
  con una referencia.

### Regla especial — cambios de seguridad / disco / arranque / auth
Los cambios que tocan **particionado de disco, el bootloader, cifrado/LUKS, PAM/sudo/FIDO2, el firewall o la
cadena de suministro** tienen el mayor radio de impacto y reciben escrutinio extra antes del merge:
1. **Revisión adversarial** — se revisa contra los hallazgos de
   [docs/audit/01](docs/audit/01-security-supply-chain.md) y
   [docs/audit/02](docs/audit/02-data-integrity-ops.md): el revisor intenta romperlo, no solo leerlo.
2. **Validación en VM** — los cambios de disco/arranque se validan en VM según
   [docs/STAGE2-VALIDATION.md](docs/STAGE2-VALIDATION.md) antes de publicarse activados.
3. **Gates de seguridad intactos** — el PR no puede debilitar: `ARCHFRICAN_ISO_ARMED` por defecto `0` (el
   instalador ISO sale en preview por defecto), los dos gates de disco (`confirm_wipe` + el opt-in de
   armado), el invariante FIDO2
   no-excluyente/sin-lockout (pam-u2f ≥ 1.3.1), el firewall de tabla-nombrada-nunca-`flush ruleset`, el pin
   de la huella de la clave de firma de CachyOS (fail-closed), `ARCHFRICAN_DEEPCLEAN_ARMED` por defecto `0`
   (el deep-clean sale en preview por defecto, el mismo patrón que `ARCHFRICAN_ISO_ARMED`), que la lista
   blanca de subvolúmenes a borrar (`DEEPCLEAN_DELETE_SUBVOLS`) siga siendo un literal fijo — nunca
   calculado desde un `btrfs subvolume list` en vivo — y que `@home` nunca aparezca en ella, y que el
   deep-clean solo opere al nivel de subvolumen btrfs, sin llamar jamás a un verbo de reformateo de disco
   completo (`mkfs.btrfs`, `cryptsetup luksFormat`, `wipefs`, `sgdisk`). Los jobs de CI `iso-safety-gate` +
   `firewall-ruleset` + `deepclean-safety-gate` hacen cumplir varios de estos mecánicamente.

### Releases y versionado
Tags semánticos (`vMAYOR.MENOR`). El historial de commits es el changelog hasta el primer release; después,
un `CHANGELOG.md` (Keep a Changelog) generado desde el log Conventional-Commit. Los tags de release se
firman (`git tag -s`) una vez configurada la firma.

### Convertirse en mantenedor
Contribuciones sostenidas y de calidad + buen criterio con las reglas de seguridad de arriba. El mantenedor
invita a nuevos mantenedores; no hay cuota fija.
