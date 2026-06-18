<!-- Thanks for contributing! / ¡Gracias por contribuir! Bilingual checklist below. -->

## What & why / Qué y por qué


## Checklist
- [ ] Conventional Commit title (`feat/fix/chore/docs/ci/refactor`) — **no AI attribution** / sin atribución de IA
- [ ] `bash -n` + `shellcheck -x -e SC1091` pass locally / pasan localmente
- [ ] Package names only in `packages/*.txt` (new list → added to CI `pkg-resolution`) / nombres solo en `packages/*.txt`
- [ ] Idempotent + reliability vocab (`die`/`best_effort`/`write_system_file`/…) / idempotente
- [ ] No plain `Mod+<letter>` niri bind; `/etc/default/grub` via `lib/grub.sh` / sin `Mod+<letra>`; grub vía helper
- [ ] In scope per [VISION.md](../VISION.md) / dentro del alcance
- [ ] If disk/boot/auth: VM-validated + safety gates intact (`ARCHFRICAN_ISO_ARMED=0`) / validado en VM, gates intactos
- [ ] Docs updated if behavior changed / docs actualizadas si cambió el comportamiento
