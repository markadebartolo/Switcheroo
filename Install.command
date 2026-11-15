#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")" && pwd)"
trap 'echo; echo "Installation did not finish. Copy the error above if you need help."; read -r -p "Press Return to close…" _' ERR
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Open Install.command on your Mac."
  exit 1
fi
if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  echo "Switcheroo needs Apple's Command Line Tools to compile."
  echo "An Apple installation dialog will open. When it finishes, run Install.command again."
  /usr/bin/xcode-select --install || true
  read -r -p "Press Return to close…" _
  exit 0
fi
bash "$app_root/scripts/build.sh"
app_destination="$HOME/Applications/Switcheroo.app"
mkdir -p "$HOME/Applications"
if [[ -e "$app_destination" ]]; then
  echo "An Switcheroo installation already exists. The new build is in:"
  echo "$app_root/build/Switcheroo.app"
  echo "Quit Switcheroo and replace your existing app in Finder when ready."
  /usr/bin/open -R "$app_root/build/Switcheroo.app"
else
  /usr/bin/ditto "$app_root/build/Switcheroo.app" "$app_destination"
  /usr/bin/open "$app_destination"
  echo "Installed in $app_destination"
fi
read -r -p "Press Return to close…" _
