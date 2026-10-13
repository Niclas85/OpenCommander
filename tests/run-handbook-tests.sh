#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
swiftc "$task_root/ios/OpenCommander/CommanderHandbook.swift" "$task_root/ios/tests/HandbookTests/main.swift" -o "$task_output/handbook-tests"
"$task_output/handbook-tests"
