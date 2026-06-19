# Governance / Gobernanza

> 🇬🇧 English first · 🇪🇸 Español a continuación.

## English

### Model
Archfrican is **maintainer-led (BDFL)**. The maintainer is **[@JAfricanoT](https://github.com/JAfricanoT)**.
Decisions are made by **lazy consensus** on issues/PRs; if there's no objection, a change moves forward. On
disagreement, the maintainer arbitrates. Only the maintainer merges to `main`.

### Merge requirements (every PR)
- **CI is green** — all gates pass (see [CONTRIBUTING.md](CONTRIBUTING.md): `shellcheck`, `bashn`,
  `firewall-ruleset`, `grub-helper`, `iso-safety-gate`, `theme-switch-smoke`, `pkg-resolution`).
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
   and the fail-closed CachyOS sha256 pin. The CI `iso-safety-gate` + `firewall-ruleset` jobs enforce two
   of these mechanically.

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
   no-excluyente/sin-lockout (pam-u2f ≥ 1.3.1), el firewall de tabla-nombrada-nunca-`flush ruleset`, y el
   pin sha256 fail-closed de CachyOS. Los jobs de CI `iso-safety-gate` + `firewall-ruleset` hacen cumplir
   dos de estos mecánicamente.

### Releases y versionado
Tags semánticos (`vMAYOR.MENOR`). El historial de commits es el changelog hasta el primer release; después,
un `CHANGELOG.md` (Keep a Changelog) generado desde el log Conventional-Commit. Los tags de release se
firman (`git tag -s`) una vez configurada la firma.

### Convertirse en mantenedor
Contribuciones sostenidas y de calidad + buen criterio con las reglas de seguridad de arriba. El mantenedor
invita a nuevos mantenedores; no hay cuota fija.
