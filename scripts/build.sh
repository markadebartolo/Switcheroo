#!/bin/bash
# Builds build/Switcheroo.app with the Swift compiler alone: no Xcode project is needed.
#
#   bash scripts/build.sh                       for this Mac's processor, signed for local use only
#   ARCHS="arm64 x86_64" SIGN_IDENTITY="Developer ID Application: …" bash scripts/build.sh
#                                               a universal build signed for distribution (see release.sh)
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Switcheroo requires macOS 13 or newer. Build this package on your Mac."
  exit 1
fi
if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple Command Line Tools are required. Run: xcode-select --install"
  exit 1
fi
app_archs="${ARCHS:-$(uname -m)}"
app_identity="${SIGN_IDENTITY:--}"
app_sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
app_app="$app_root/build/Switcheroo.app"
/bin/rm -rf "$app_app"
mkdir -p "$app_app/Contents/MacOS" "$app_app/Contents/Resources" "$app_root/build/module-cache" "$app_root/build/thin"
cp "$app_root/Resources/Info.plist" "$app_app/Contents/Info.plist"
app_sparkle="$(/bin/bash "$app_root/scripts/fetch-sparkle.sh" | /usr/bin/tail -1)"
app_slices=()
for app_arch in $app_archs; do
  echo "Compiling Switcheroo for ${app_arch}..."
  /usr/bin/xcrun swiftc -O -swift-version 5 \
    -target "${app_arch}-apple-macosx13.0" -sdk "$app_sdk" \
    -module-cache-path "$app_root/build/module-cache" \
    -module-name Switcheroo \
    -framework AppKit -framework PDFKit -framework ImageIO \
    -framework Vision -framework CoreImage -framework UniformTypeIdentifiers -framework QuartzCore \
    -F "$app_sparkle" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "$app_root"/Sources/Switcheroo/*.swift \
    -o "$app_root/build/thin/Switcheroo-${app_arch}"
  app_slices+=("$app_root/build/thin/Switcheroo-${app_arch}")
done
/usr/bin/lipo -create "${app_slices[@]}" -output "$app_app/Contents/MacOS/Switcheroo"
# Sparkle, which checks for and installs updates, travels inside the app.
mkdir -p "$app_app/Contents/Frameworks"
/usr/bin/ditto "$app_sparkle/Sparkle.framework" "$app_app/Contents/Frameworks/Sparkle.framework"
echo "Generating app icon..."
/usr/bin/xcrun swift -module-cache-path "$app_root/build/module-cache" \
  "$app_root/scripts/make-icon.swift" "$app_root/build/Switcheroo.iconset"
/usr/bin/iconutil --convert icns "$app_root/build/Switcheroo.iconset" \
  --output "$app_app/Contents/Resources/Switcheroo.icns"
if [[ "$app_identity" == "-" ]]; then
  app_sign=(/usr/bin/codesign --force --sign -)
else
  # For distribution: the hardened runtime and a secure timestamp, both of which Apple's notary requires.
  app_sign=(/usr/bin/codesign --force --options runtime --timestamp --sign "$app_identity")
fi
# Inside out: Sparkle's helpers first, then the framework, then the app (the order Sparkle documents).
app_sparkle_b="$app_app/Contents/Frameworks/Sparkle.framework/Versions/B"
"${app_sign[@]}" "$app_sparkle_b/XPCServices/Installer.xpc"
"${app_sign[@]}" --preserve-metadata=entitlements "$app_sparkle_b/XPCServices/Downloader.xpc"
"${app_sign[@]}" "$app_sparkle_b/Autoupdate"
"${app_sign[@]}" "$app_sparkle_b/Updater.app"
"${app_sign[@]}" "$app_app/Contents/Frameworks/Sparkle.framework"
"${app_sign[@]}" "$app_app"
/usr/bin/codesign --verify --deep --strict "$app_app"
echo "Running image-processing checks..."
"$app_app/Contents/MacOS/Switcheroo" --self-test
echo "Built: $app_app"
