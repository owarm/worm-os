# Worm OS architecture

Worm OS is maintained as a downstream layer on top of GrapheneOS.

Target device:

- Google Pixel 10
- GrapheneOS device codename: frankel
- Kernel family: muzel

Repositories:

- worm-os: OS integration, configuration and patches
- worm-home: Worm launcher
- worm-store: Worm application distribution
- worm-installer: web installer

Design principle:

GrapheneOS source is kept upstream.
Worm-specific modifications are maintained separately as patches,
overlays and integration configuration.

This makes upstream GrapheneOS updates auditable and allows Worm
changes to be reapplied to a newer upstream release.
