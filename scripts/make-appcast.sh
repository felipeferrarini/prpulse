#!/usr/bin/env bash
# Signs build/PRPulse-<version>.dmg with the Sparkle key from the login keychain and writes build/feed/appcast.xml.
# Upload both files to the GitHub release: the app reads the feed from releases/latest/download/appcast.xml.
# Usage: scripts/make-appcast.sh [version]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/config.sh"
version="${1:-0.1.0}"

dmg="$root/build/$APP_NAME-$version.dmg"
tool="$root/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
[ -f "$dmg" ] || { echo "missing $dmg (run make dmg first)" >&2; exit 1; }
[ -x "$tool" ] || { echo "missing $tool (run swift package resolve)" >&2; exit 1; }

feed="$root/build/feed"
rm -rf "$feed"
mkdir -p "$feed"
cp "$dmg" "$feed/"

"$tool" --download-url-prefix "https://github.com/felipeferrarini/prpulse/releases/download/v$version/" "$feed"
echo "built: $feed/appcast.xml"
