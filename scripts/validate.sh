#!/bin/bash
set -euo pipefail
orbit_root="$(cd "$(dirname "$0")/.." && pwd)"
orbit_log="${orbit_root}/validation.log"
orbit_app="${orbit_root}/build/OrbitDrop.app"
exec > >(tee "${orbit_log}") 2>&1
printf 'OrbitDrop validation %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf 'OS: %s %s\n' "$(uname -s)" "$(uname -m)"
/usr/bin/xcodebuild -version
/usr/bin/xcrun swift --version
printf 'SDK: %s\n' "$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
# Only the ignored, generated build directory is removed.
/bin/rm -rf "${orbit_root}/build"
/bin/bash "${orbit_root}/scripts/build.sh"
test -x "${orbit_app}/Contents/MacOS/OrbitDrop"
test -s "${orbit_app}/Contents/Resources/OrbitDrop.icns"
/usr/bin/plutil -lint "${orbit_app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${orbit_app}/Contents/Info.plist"
/usr/bin/file "${orbit_app}/Contents/MacOS/OrbitDrop"
/usr/bin/xcrun vtool -show-build "${orbit_app}/Contents/MacOS/OrbitDrop"
/usr/bin/codesign --verify --strict --verbose=2 "${orbit_app}"
/usr/bin/codesign -dv "${orbit_app}" 2>&1
"${orbit_app}/Contents/MacOS/OrbitDrop" --self-test
printf 'CLEAN RELEASE VALIDATION PASSED: %s\n' "${orbit_app}"
