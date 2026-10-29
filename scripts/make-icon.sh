#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

swift "$root/scripts/make-icon.swift" "$work/AppIcon.iconset"
iconutil -c icns "$work/AppIcon.iconset" -o "$root/Resources/AppIcon.icns"
echo "wrote: $root/Resources/AppIcon.icns"
