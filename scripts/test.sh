#!/usr/bin/env bash
# Runs the test suite. With only the Command Line Tools installed, incremental
# builds lose the Swift Testing macro plugin, so its path is passed explicitly.
# Usage: scripts/test.sh [swift test args]
set -euo pipefail

args=("$@")
plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$plugins" ]; then
    args+=(-Xswiftc -plugin-path -Xswiftc "$plugins")
fi

exec swift test "${args[@]}"
