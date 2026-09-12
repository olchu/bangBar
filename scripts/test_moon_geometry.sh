#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/bangbar-moon-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -module-cache-path "$test_dir/module-cache" \
    "$project_dir/BangBar/MoonOrientation.swift" \
    "$project_dir/BangBar/MoonIlluminationMask.swift" \
    "$project_dir/Tests/MoonGeometryTests.swift" \
    -o "$test_dir/moon-tests"
"$test_dir/moon-tests"
