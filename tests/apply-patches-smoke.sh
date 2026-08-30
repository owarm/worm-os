#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

WORM_ROOT="$TMP/worm"
GRAPHENE_ROOT="$TMP/graphene"
PROJECT="packages/apps/Settings"
PATCH_NAME="0001-example.patch"

mkdir -p \
    "$WORM_ROOT/config" \
    "$WORM_ROOT/scripts" \
    "$WORM_ROOT/patches/graphene/$PROJECT" \
    "$GRAPHENE_ROOT/.repo" \
    "$GRAPHENE_ROOT/$PROJECT"

cp "$ROOT/scripts/apply-patches.sh" "$WORM_ROOT/scripts/apply-patches.sh"

cat >"$WORM_ROOT/config/frankel.conf" <<EOF
WORM_PATCH_DIR="patches/graphene"
GRAPHENE_SOURCE_DIR="$GRAPHENE_ROOT"
EOF

git -C "$GRAPHENE_ROOT/$PROJECT" init -q
printf 'before\n' >"$GRAPHENE_ROOT/$PROJECT/target.txt"

cat >"$WORM_ROOT/patches/graphene/$PROJECT/$PATCH_NAME" <<'EOF'
--- a/target.txt
+++ b/target.txt
@@ -1 +1 @@
-before
+after
EOF

"$WORM_ROOT/scripts/apply-patches.sh" >"$TMP/apply.log"

grep -F "Applying: $PROJECT / $PATCH_NAME" "$TMP/apply.log" >/dev/null
grep -qx 'after' "$GRAPHENE_ROOT/$PROJECT/target.txt"
