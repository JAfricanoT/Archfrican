# migrations/ — versioned one-shot fixes for *old* installs

These run **only** when updating an already-installed Archfrican, never on a fresh install. They
are the one place where "update" legitimately differs from "install nuevo": a clean install starts
at the desired state, but an old machine may carry **stale state** the new desired state no longer
describes — a config that was renamed, a service that was retired, a drop-in that moved. A migration
*undoes* that old state.

The idempotent module re-converge (driven by `lib/converge.sh`) already brings the *current*
desired state into place. Migrations only handle what convergence can't see: things that should no
longer exist.

## Contract
- File name: `NNNN-slug.sh` — a zero-padded integer prefix (`0001`, `0002`, …) sets the order.
- Each migration is **idempotent** and a **no-op on a fresh system** (it removes/fixes old state
  that a clean install never created).
- `set -euo pipefail`; use `sudo` for privileged steps; print a one-line `✓` result.
- It must **exit non-zero only on a real failure** (`lib/migrate.sh::run_migrations` aborts the
  update on a failed migration so nothing half-applies).

## How it's tracked
`lib/migrate.sh` records the applied version in `/var/lib/archfrican/state-version`:
- **No `state-version`** (fresh install) → marked straight to the latest, **nothing runs**.
- **Older version** → every `NNNN` greater than it runs in order, recording progress after each.
- `archfrican-doctor` reports any pending count as drift; `archfrican-update --run` applies them
  (after the repo refresh, before the module converge).

## Adding one
1. Create `migrations/NNNN-slug.sh` (next number).
2. Make it idempotent + a fresh-system no-op.
3. The CI `migrations-idempotent` gate runs the suite twice and asserts the second run is a no-op.
