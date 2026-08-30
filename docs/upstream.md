# GrapheneOS Upstream

Worm OS tracks GrapheneOS as upstream through the public manifest:

- Manifest: `https://github.com/GrapheneOS/platform_manifest.git`
- Branch: `17`
- Device: Google Pixel 10 (`frankel`)
- Kernel family: `muzel`

The upstream checkout is configured by `GRAPHENE_SOURCE_DIR` in
`config/frankel.conf` and defaults to `$HOME/grapheneos-frankel-17`. That
path is deliberately outside this repository and is ignored when common local
checkout names are used.

## Sync Policy

Use `scripts/sync-graphene.sh` to initialize or update the external checkout.
The script refuses to place GrapheneOS inside `worm-os`, validates the
destination before modifying it, and uses the Android `repo` tool for sync.

## Patch Policy

Use `scripts/apply-patches.sh` after syncing upstream. Patches are checked
before they are applied. If a patch fails validation, the script reports a
patch conflict and exits without force-applying it.

Conflicts must be resolved by reviewing the upstream GrapheneOS change,
refreshing the Worm patch, and submitting the refreshed patch for review.
