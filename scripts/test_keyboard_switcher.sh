#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/bangbar-keyboard-buffer.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

xcrun swiftc \
    -module-cache-path "$test_dir/module-cache" \
    "$project_dir/BangBar/KeyboardWordBuffer.swift" \
    "$project_dir/Tests/KeyboardWordBufferTests.swift" \
    -o "$test_dir/keyboard-buffer-tests"
"$test_dir/keyboard-buffer-tests"

xcrun swiftc \
    -module-cache-path "$test_dir/module-cache" \
    "$project_dir/BangBar/KeyboardAutoSwitchRules.swift" \
    "$project_dir/Tests/KeyboardAutoSwitchRulesTests.swift" \
    -o "$test_dir/keyboard-auto-switch-tests"
"$test_dir/keyboard-auto-switch-tests"

xcrun swiftc \
    -module-cache-path "$test_dir/module-cache" \
    "$project_dir/BangBar/KeyboardLearnedWords.swift" \
    "$project_dir/BangBar/KeyboardAutoSwitchRules.swift" \
    "$project_dir/Tests/KeyboardLearnedWordsTests.swift" \
    -o "$test_dir/keyboard-learned-words-tests"
"$test_dir/keyboard-learned-words-tests"
