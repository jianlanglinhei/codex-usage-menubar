#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$PROJECT_ROOT/build/CodexUsage.app"
SPARKLE=$("$PROJECT_ROOT/scripts/sparkle.sh")
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$PROJECT_ROOT"/Resources/*.lproj "$APP/Contents/Resources/"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Frameworks"
# Preserve framework symlinks; sign nested components before the app.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
MACOSX_DEPLOYMENT_TARGET=13.0 xcrun swiftc -O \
  "$PROJECT_ROOT"/Sources/*.swift \
  -o "$APP/Contents/MacOS/CodexUsage" \
  -framework AppKit -framework IOKit -framework SwiftUI -framework ServiceManagement -framework UserNotifications \
  -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then SIGN_FLAGS+=(--options runtime --timestamp); fi
for COMPONENT in "$FRAMEWORK/XPCServices/Downloader.xpc" "$FRAMEWORK/XPCServices/Installer.xpc" "$FRAMEWORK/Autoupdate" "$FRAMEWORK/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
  if [[ -e "$COMPONENT" ]]; then codesign "${SIGN_FLAGS[@]}" "$COMPONENT"; fi
done
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
printf 'Built: %s\n' "$APP"
