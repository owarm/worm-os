# GrapheneOS upstream

Manifest:
https://github.com/GrapheneOS/platform_manifest

Development branch:
17

Worm OS target:
frankel

The GrapheneOS source tree is not vendored into the worm-os repository.

Instead:

1. GrapheneOS is synchronized independently.
2. Worm OS records its target and upstream branch.
3. Worm-specific patches are applied after synchronization.
4. Conflicts introduced by upstream changes are reviewed manually.

Never force-apply patches which fail validation.
