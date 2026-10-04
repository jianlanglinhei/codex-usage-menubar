#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$PROJECT_ROOT/build/CodexUsage.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$PROJECT_ROOT"/Resources/*.lproj "$APP/Contents/Resources/"
MACOSX_DEPLOYMENT_TARGET=13.0 xcrun swiftc -O \
  "$PROJECT_ROOT"/Sources/*.swift \
  -o "$APP/Contents/MacOS/CodexUsage" \
  -framework AppKit -framework IOKit -framework SwiftUI -framework ServiceManagement
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
