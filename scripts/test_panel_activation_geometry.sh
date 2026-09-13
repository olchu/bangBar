#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/bangbar-panel-geometry.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

xcrun swiftc \
    -module-cache-path "$test_dir/module-cache" \
    "$project_dir/BangBar/PanelActivationGeometry.swift" \
    "$project_dir/Tests/PanelActivationGeometryTests.swift" \
    -o "$test_dir/panel-geometry-tests"
"$test_dir/panel-geometry-tests"
