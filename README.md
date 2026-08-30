# Worm OS

Worm OS is a downstream Android operating-system project based on
GrapheneOS.

Primary target:

**Google Pixel 10 (`frankel`)**

## Components

- Worm OS — system integration
- Worm Home — launcher
- Worm Store — application distribution
- Worm Installer — web installation interface

## Upstream model

GrapheneOS remains the upstream source.

Worm-specific changes are stored as:

- configuration
- patches
- resource overlays
- integration scripts

This repository does not contain private signing keys, credentials or
production secrets.

## Branches

`main`

Stable Worm OS repository configuration.

`graphene-frankel`

GrapheneOS synchronization and Worm patch development for Pixel 10.

## Basic workflow

Sync GrapheneOS:

    ./scripts/sync-graphene.sh

Apply Worm patches:

    ./scripts/apply-patches.sh

Check state:

    ./scripts/status.sh
