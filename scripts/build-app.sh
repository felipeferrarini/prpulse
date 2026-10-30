#!/usr/bin/env bash
# Builds a universal, ad-hoc signed PRPulse.app into build/.
# Usage: scripts/build-app.sh [version]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/config.sh"
version="${1:-0.1.0}"

cd "$root"
# Drop stale resource bundles so renamed or removed resources never ship.
find "$root/.build-release" -name "*_$APP_NAME.bundle" -prune -exec rm -rf {} + 2>/dev/null || true

build_flags=(-c release --arch arm64 --arch x86_64 --scratch-path "$root/.build-release")
swift build "${build_flags[@]}"
bin_dir="$(swift build "${build_flags[@]}" --show-bin-path)"

app="$root/build/$APP_NAME.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$bin_dir/$APP_NAME" "$app/Contents/MacOS/$APP_NAME"
sed -e "s/__APP_NAME__/$APP_NAME/g" \
    -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
    -e "s/__VERSION__/$version/g" \
    -e "s/__MIN_MACOS__/$MIN_MACOS/g" \
    -e "s|__FEED_URL__|$FEED_URL|g" \
    -e "s|__UPDATE_PUBLIC_KEY__|$UPDATE_PUBLIC_KEY|g" \
    "$root/Resources/Info.plist.template" > "$app/Contents/Info.plist"

cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"

for bundle in "$bin_dir"/*_"$APP_NAME".bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$app/Contents/Resources/"
done

# Sparkle ships next to the binary; its helpers are signed first, then the whole bundle.
mkdir -p "$app/Contents/Frameworks"
cp -R "$bin_dir/Sparkle.framework" "$app/Contents/Frameworks/"
install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/$APP_NAME"

codesign --force --deep -s - "$app/Contents/Frameworks/Sparkle.framework"
codesign --force --deep -s - "$app"
echo "built: $app"
