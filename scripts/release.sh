#!/bin/bash
# Makes the download: a universal Switcheroo.app signed with a Developer ID, notarized by Apple, stapled,
# and zipped as dist/Switcheroo-macos.zip.
#
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="your-profile" bash scripts/release.sh
#
# NOTARY_PROFILE is the name of a notarytool keychain profile, made once with
#   xcrun notarytool store-credentials "your-profile" --apple-id … --team-id … --password …
# No password is read from or written to this repository. Running this script sends the app to Apple.
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool keychain profile}"
app_app="$app_root/build/Switcheroo.app"
app_dist="$app_root/dist"
app_zip="$app_dist/Switcheroo-macos.zip"

ARCHS="arm64 x86_64" SIGN_IDENTITY="$SIGN_IDENTITY" /bin/bash "$app_root/scripts/build.sh"
mkdir -p "$app_dist"
/bin/rm -f "$app_zip"
/usr/bin/ditto -c -k --keepParent "$app_app" "$app_zip"

echo "Sending to Apple's notary service..."
/usr/bin/xcrun notarytool submit "$app_zip" --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$app_app"
/usr/bin/xcrun stapler validate "$app_app"
/usr/sbin/spctl --assess --type execute --verbose=2 "$app_app"

# The zip that people download holds the stapled app.
/bin/rm -f "$app_zip"
/usr/bin/ditto -c -k --keepParent "$app_app" "$app_zip"
/usr/bin/shasum -a 256 "$app_zip"
echo "Ready to attach to a GitHub release: $app_zip"
