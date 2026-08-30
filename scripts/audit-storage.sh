#!/bin/bash

ROOT=/opt/Android/worm-os
UPSTREAM="$ROOT/upstream"

echo "=== FILESYSTEM ==="
df -h "$ROOT"

echo
echo "=== WORM-OS TOP LEVEL ==="
du -xh --max-depth=1 "$ROOT" 2>/dev/null | sort -h

echo
echo "=== UPSTREAM TOP LEVEL ==="
du -xh --max-depth=1 "$UPSTREAM" 2>/dev/null | sort -h | tail -30

echo
echo "=== .repo ==="
du -xh --max-depth=2 "$UPSTREAM/.repo" 2>/dev/null |
    sort -h |
    tail -30

echo
echo "=== WORK TREE EXCLUDING .repo ==="
du -sh --exclude=.repo "$UPSTREAM" 2>/dev/null

echo
echo "=== REPO OBJECTS ==="
du -sh \
    "$UPSTREAM/.repo/project-objects" \
    "$UPSTREAM/.repo/projects" \
    2>/dev/null || true

echo
echo "=== OTHER /opt/Android PROJECTS ==="
du -xh --max-depth=1 /opt/Android 2>/dev/null |
    sort -h |
    tail -25

echo
echo "WORM_STORAGE_AUDIT=PASS"
