# Worm OS Architecture

Worm OS is maintained as a downstream integration layer on top of
GrapheneOS. The initial target is Google Pixel 10 (`frankel`) using the
GrapheneOS `17` branch and the `muzel` kernel family.

## Source Model

The complete GrapheneOS source checkout lives outside this Git repository.
`worm-os` tracks only the material needed to reproduce and review Worm
changes:

- Target configuration in `config/`.
- Frankel-specific overlays in `overlays/frankel/`.
- Reviewable GrapheneOS patches in `patches/graphene/`.
- Operational scripts in `scripts/`.
- Design and process documentation in `docs/`.

This keeps upstream GrapheneOS history authoritative and makes Worm changes
small enough to audit during every rebase or branch refresh.

## Integration Boundaries

`worm-os` owns OS integration and GrapheneOS adaptation. The following
projects are intentionally separate and should be consumed through explicit
integration steps later:

- `owarm/worm-home` for the launcher and home experience.
- `owarm/worm-store` for application distribution.
- `owarm/worm-installer` for installation and flashing workflows.

Future integrations should add configuration, overlays, or patches here only
when they are needed by the OS build. Application source should remain in its
own repository unless a reviewed build rule requires otherwise.

## Patch Layout

GrapheneOS patches are stored as:

```text
patches/graphene/<upstream-project>/<patch-name>.patch
```

`scripts/apply-patches.sh` maps `<upstream-project>` to a Git project inside
the external GrapheneOS checkout and validates each patch with
`git apply --check` before applying it.
