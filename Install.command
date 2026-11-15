#!/bin/bash
set -euo pipefail
orbit_root="$(cd "$(dirname "$0")" && pwd)"
trap 'echo; echo "Installation did not finish. Copy the error above if you need help."; read -r -p "Press Return to close…" _' ERR
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Open Install.command on your Mac."
  exit 1
fi
if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  echo "OrbitDrop needs Apple's Command Line Tools to compile."
  echo "An Apple installation dialog will open. When it finishes, run Install.command again."
  /usr/bin/xcode-select --install || true
  read -r -p "Press Return to close…" _
  exit 0
fi
bash "$orbit_root/scripts/build.sh"
orbit_destination="$HOME/Applications/OrbitDrop.app"
mkdir -p "$HOME/Applications"
if [[ -e "$orbit_destination" ]]; then
  echo "An OrbitDrop installation already exists. The new build is in:"
  echo "$orbit_root/build/OrbitDrop.app"
  echo "Quit OrbitDrop and replace your existing app in Finder when ready."
  /usr/bin/open -R "$orbit_root/build/OrbitDrop.app"
else
  /usr/bin/ditto "$orbit_root/build/OrbitDrop.app" "$orbit_destination"
  /usr/bin/open "$orbit_destination"
  echo "Installed in $orbit_destination"
fi
read -r -p "Press Return to close…" _
