#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$PROJECT_ROOT/build/CodexUsage.app"
mkdir -p "$APP/Contents/MacOS"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
MACOSX_DEPLOYMENT_TARGET=13.0 xcrun swiftc -O \
  "$PROJECT_ROOT/Sources/main.swift" \
  "$PROJECT_ROOT/Sources/SleepKeeper.swift" \
  "$PROJECT_ROOT/Sources/ResetForecast.swift" \
  -o "$APP/Contents/MacOS/CodexUsage" -framework AppKit -framework IOKit
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
