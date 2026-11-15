#!/bin/bash
# Builds build/OrbitDrop.app with the Swift compiler alone: no Xcode project is needed.
#
#   bash scripts/build.sh                       for this Mac's processor, signed for local use only
#   ARCHS="arm64 x86_64" SIGN_IDENTITY="Developer ID Application: …" bash scripts/build.sh
#                                               a universal build signed for distribution (see release.sh)
set -euo pipefail
orbit_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "OrbitDrop requires macOS 13 or newer. Build this package on your Mac."
  exit 1
fi
if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple Command Line Tools are required. Run: xcode-select --install"
  exit 1
fi
orbit_archs="${ARCHS:-$(uname -m)}"
orbit_identity="${SIGN_IDENTITY:--}"
orbit_sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
orbit_app="$orbit_root/build/OrbitDrop.app"
/bin/rm -rf "$orbit_app"
mkdir -p "$orbit_app/Contents/MacOS" "$orbit_app/Contents/Resources" "$orbit_root/build/module-cache" "$orbit_root/build/thin"
cp "$orbit_root/Resources/Info.plist" "$orbit_app/Contents/Info.plist"
orbit_slices=()
for orbit_arch in $orbit_archs; do
  echo "Compiling OrbitDrop for ${orbit_arch}..."
  /usr/bin/xcrun swiftc -O -swift-version 5 \
    -target "${orbit_arch}-apple-macosx13.0" -sdk "$orbit_sdk" \
    -module-cache-path "$orbit_root/build/module-cache" \
    -module-name OrbitDrop \
    -framework AppKit -framework PDFKit -framework ImageIO \
    -framework Vision -framework CoreImage -framework UniformTypeIdentifiers -framework QuartzCore \
    "$orbit_root"/Sources/OrbitDrop/*.swift \
    -o "$orbit_root/build/thin/OrbitDrop-${orbit_arch}"
  orbit_slices+=("$orbit_root/build/thin/OrbitDrop-${orbit_arch}")
done
/usr/bin/lipo -create "${orbit_slices[@]}" -output "$orbit_app/Contents/MacOS/OrbitDrop"
echo "Generating app icon..."
/usr/bin/xcrun swift -module-cache-path "$orbit_root/build/module-cache" \
  "$orbit_root/scripts/make-icon.swift" "$orbit_root/build/OrbitDrop.iconset"
/usr/bin/iconutil --convert icns "$orbit_root/build/OrbitDrop.iconset" \
  --output "$orbit_app/Contents/Resources/OrbitDrop.icns"
if [[ "$orbit_identity" == "-" ]]; then
  /usr/bin/codesign --force --sign - "$orbit_app"
else
  # For distribution: the hardened runtime and a secure timestamp, both of which Apple's notary requires.
  /usr/bin/codesign --force --options runtime --timestamp --sign "$orbit_identity" "$orbit_app"
fi
/usr/bin/codesign --verify --strict "$orbit_app"
echo "Running image-processing checks..."
"$orbit_app/Contents/MacOS/OrbitDrop" --self-test
echo "Built: $orbit_app"
