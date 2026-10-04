#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$PROJECT_ROOT/scripts/build.sh"
APP="$PROJECT_ROOT/build/CodexUsage.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(/usr/bin/lipo -archs "$APP/Contents/MacOS/CodexUsage" | tr ' ' '-')
OUTPUT="$PROJECT_ROOT/build/releases/$VERSION"
ARCHIVE="CodexUsage-$VERSION-macos-$ARCH.zip"
mkdir -p "$OUTPUT"
# Recreate the archive after stapling so offline Gatekeeper checks see the ticket.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/$ARCHIVE"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  if [[ "${CODE_SIGN_IDENTITY:--}" == "-" ]]; then
    echo 'Notarization requires CODE_SIGN_IDENTITY.' >&2
    exit 1
  fi
  xcrun notarytool submit "$OUTPUT/$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$APP"
  rm "$OUTPUT/$ARCHIVE"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/$ARCHIVE"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
(cd "$OUTPUT" && shasum -a 256 "$ARCHIVE" > SHA256SUMS)
printf 'Release artifacts: %s\n' "$OUTPUT"
