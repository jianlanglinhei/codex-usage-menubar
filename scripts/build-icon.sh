#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_ROOT/build"
ICON_WORK=$(mktemp -d "$PROJECT_ROOT/build/.icon.XXXXXX")
trap 'rm -rf "$ICON_WORK"' EXIT
ICON_SET="$ICON_WORK/AppIcon.iconset"
mkdir -p "$ICON_SET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$PROJECT_ROOT/Resources/AppIcon.png" --out "$ICON_SET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$PROJECT_ROOT/Resources/AppIcon.png" --out "$ICON_SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_SET" -o "$PROJECT_ROOT/Resources/AppIcon.icns"
