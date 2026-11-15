#!/bin/bash
# Makes the download: a universal OrbitDrop.app signed with a Developer ID, notarized by Apple, stapled,
# and zipped as dist/OrbitDrop-macos.zip.
#
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="your-profile" bash scripts/release.sh
#
# NOTARY_PROFILE is the name of a notarytool keychain profile, made once with
#   xcrun notarytool store-credentials "your-profile" --apple-id … --team-id … --password …
# No password is read from or written to this repository. Running this script sends the app to Apple.
set -euo pipefail
orbit_root="$(cd "$(dirname "$0")/.." && pwd)"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool keychain profile}"
orbit_app="$orbit_root/build/OrbitDrop.app"
orbit_dist="$orbit_root/dist"
orbit_zip="$orbit_dist/OrbitDrop-macos.zip"

ARCHS="arm64 x86_64" SIGN_IDENTITY="$SIGN_IDENTITY" /bin/bash "$orbit_root/scripts/build.sh"
mkdir -p "$orbit_dist"
/bin/rm -f "$orbit_zip"
/usr/bin/ditto -c -k --keepParent "$orbit_app" "$orbit_zip"

echo "Sending to Apple's notary service..."
/usr/bin/xcrun notarytool submit "$orbit_zip" --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$orbit_app"
/usr/bin/xcrun stapler validate "$orbit_app"
/usr/sbin/spctl --assess --type execute --verbose=2 "$orbit_app"

# The zip that people download holds the stapled app.
/bin/rm -f "$orbit_zip"
/usr/bin/ditto -c -k --keepParent "$orbit_app" "$orbit_zip"
/usr/bin/shasum -a 256 "$orbit_zip"
echo "Ready to attach to a GitHub release: $orbit_zip"
