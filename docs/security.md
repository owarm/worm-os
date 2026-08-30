# Security Policy

Worm OS preserves GrapheneOS security features by default. Security-sensitive
changes require explicit review and should be isolated in small patches with a
clear rationale.

This repository must never contain:

- Private signing keys or keystores.
- Recovery, update, verified boot, or release signing material.
- Credentials, tokens, API keys, or production secrets.
- Complete vendored GrapheneOS source trees.

The scripts in this repository fail closed where practical:

- They use `set -euo pipefail`.
- They validate configured paths before modifying external checkouts.
- They refuse obvious signing-material and secret paths.
- They check patches before applying them.
- They report patch conflicts clearly and stop instead of force-applying.

Signing material should be managed by a separate, access-controlled release
process. Build and integration scripts added here must treat signing paths as
inputs owned by that process, not as repository content.
