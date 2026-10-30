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

# The update window shows this version's section of the changelog as its release notes.
notes="$feed/$APP_NAME-$version.md"
awk -v header="## [$version]" '
    index($0, header) == 1 { printing = 1; next }
    /^## \[/ { printing = 0 }
    printing
' "$root/CHANGELOG.md" | sed -e '/./,$!d' > "$notes"
[ -s "$notes" ] || { echo "no CHANGELOG.md section for $version" >&2; exit 1; }

"$tool" --embed-release-notes --download-url-prefix "https://github.com/felipeferrarini/prpulse/releases/download/v$version/" "$feed"
echo "built: $feed/appcast.xml"
