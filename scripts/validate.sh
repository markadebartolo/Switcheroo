#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
app_log="${app_root}/validation.log"
app_app="${app_root}/build/Switcheroo.app"
exec > >(tee "${app_log}") 2>&1
printf 'Switcheroo validation %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf 'OS: %s %s\n' "$(uname -s)" "$(uname -m)"
/usr/bin/xcodebuild -version
/usr/bin/xcrun swift --version
printf 'SDK: %s\n' "$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
# Only the ignored, generated build directory is removed.
/bin/rm -rf "${app_root}/build"
/bin/bash "${app_root}/scripts/build.sh"
test -x "${app_app}/Contents/MacOS/Switcheroo"
test -s "${app_app}/Contents/Resources/Switcheroo.icns"
/usr/bin/plutil -lint "${app_app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${app_app}/Contents/Info.plist"
/usr/bin/file "${app_app}/Contents/MacOS/Switcheroo"
/usr/bin/xcrun vtool -show-build "${app_app}/Contents/MacOS/Switcheroo"
/usr/bin/codesign --verify --strict --verbose=2 "${app_app}"
/usr/bin/codesign -dv "${app_app}" 2>&1
"${app_app}/Contents/MacOS/Switcheroo" --self-test
printf 'CLEAN RELEASE VALIDATION PASSED: %s\n' "${app_app}"
