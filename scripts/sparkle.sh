#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=2.10.0
SHA=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
CACHE="$PROJECT_ROOT/build/vendor/sparkle-$VERSION"
if [[ ! -f "$CACHE/.verified-$SHA" ]]; then
  mkdir -p "$PROJECT_ROOT/build/vendor"
  ARCHIVE="$PROJECT_ROOT/build/vendor/Sparkle-$VERSION.tar.xz"
  if [[ ! -f "$ARCHIVE" ]]; then
    curl --fail --location --retry 2 "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" -o "$ARCHIVE.tmp"
    mv "$ARCHIVE.tmp" "$ARCHIVE"
  fi
  printf '%s  %s\n' "$SHA" "$ARCHIVE" | shasum -a 256 -c - >&2
  mkdir -p "$CACHE"
  tar -xf "$ARCHIVE" -C "$CACHE"
  touch "$CACHE/.verified-$SHA"
fi
printf '%s\n' "$CACHE"
