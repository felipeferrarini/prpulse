#!/usr/bin/env bash
# Builds build/PRPulse-<version>.dmg with the app and an /Applications shortcut.
# Usage: scripts/make-dmg.sh [version]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/config.sh"
version="${1:-0.1.0}"

bash "$root/scripts/build-app.sh" "$version"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$root/build/$APP_NAME.app" "$stage/"
ln -s /Applications "$stage/Applications"

dmg="$root/build/$APP_NAME-$version.dmg"
rm -f "$dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$stage" -ov -format UDZO "$dmg" > /dev/null
echo "built: $dmg"
