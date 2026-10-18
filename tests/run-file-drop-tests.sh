#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d -t opencommander-file-drop-tests)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
xcrun swiftc "$task_root/ios/OpenCommander/FileDropTransfer.swift" \
    "$task_root/ios/tests/FileDropTests/main.swift" -o "$task_output/drop-tests"
"$task_output/drop-tests"
