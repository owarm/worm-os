# Worm OS

Worm OS is a downstream Android OS integration repository for GrapheneOS.
The active target is Google Pixel 10 (`frankel`) on the GrapheneOS `17`
branch with the `muzel` kernel family.

GrapheneOS remains upstream. This repository stores Worm-specific
configuration, overlays, scripts, and reviewable patches only. It must not
vendor the complete GrapheneOS source tree or contain private signing keys,
credentials, tokens, or production secrets.

## Repository Layout

- `config/frankel.conf` - target configuration for Pixel 10.
- `docs/` - architecture, upstream, and security notes.
- `overlays/frankel/` - future frankel-specific overlay files.
- `patches/graphene/` - GrapheneOS patches arranged by upstream project.
- `scripts/` - sync, patch, and status tooling.

Adjacent projects are expected to integrate later as separate repositories:

- `owarm/worm-home`
- `owarm/worm-store`
- `owarm/worm-installer`

## Workflow

Review the configured target:

```sh
./scripts/status.sh
```

Synchronize GrapheneOS outside this repository:

```sh
./scripts/sync-graphene.sh
```

Apply Worm patches after sync:

```sh
./scripts/apply-patches.sh
```

Patch conflicts stop the run and must be reviewed manually. Do not
force-apply failed patches.
