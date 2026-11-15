#!/bin/bash
# Fetches the Sparkle update framework (https://sparkle-project.org) into vendor/, which is not committed.
# The version is pinned and the download is checked against a known SHA-256 before it is unpacked.
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
sparkle_version="2.10.1"
sparkle_sha256="${SPARKLE_SHA256:-1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27}"
sparkle_dir="$app_root/vendor/Sparkle-$sparkle_version"
if [[ -d "$sparkle_dir/Sparkle.framework" ]]; then
  echo "$sparkle_dir"
  exit 0
fi
mkdir -p "$app_root/vendor"
sparkle_archive="$app_root/vendor/Sparkle-$sparkle_version.tar.xz"
/usr/bin/curl --fail --location --silent --show-error \
  "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz" \
  --output "$sparkle_archive"
sparkle_found="$(/usr/bin/shasum -a 256 "$sparkle_archive" | /usr/bin/awk '{print $1}')"
if [[ "$sparkle_found" != "$sparkle_sha256" ]]; then
  echo "Sparkle $sparkle_version did not match its expected checksum." >&2
  echo "  expected $sparkle_sha256" >&2
  echo "  found    $sparkle_found" >&2
  /bin/rm -f "$sparkle_archive"
  exit 1
fi
mkdir -p "$sparkle_dir"
/usr/bin/tar -xf "$sparkle_archive" -C "$sparkle_dir"
/bin/rm -f "$sparkle_archive"
echo "$sparkle_dir"
