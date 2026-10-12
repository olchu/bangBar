#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/bangbar-countdown-formatter.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

xcrun swiftc \
    -module-cache-path "$test_dir/module-cache" \
    "$project_dir/BangBar/CountdownFormatter.swift" \
    "$project_dir/Tests/CountdownFormatterTests.swift" \
    -o "$test_dir/countdown-formatter-tests"
"$test_dir/countdown-formatter-tests"
