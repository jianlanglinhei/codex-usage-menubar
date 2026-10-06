#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$PROJECT_ROOT/build/CodexUsage.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$PROJECT_ROOT"/Resources/*.lproj "$APP/Contents/Resources/"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
MACOSX_DEPLOYMENT_TARGET=13.0 xcrun swiftc -O \
  "$PROJECT_ROOT"/Sources/*.swift \
  -o "$APP/Contents/MacOS/CodexUsage" \
  -framework AppKit -framework IOKit -framework SwiftUI -framework ServiceManagement
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
printf 'Built: %s\n' "$APP"
