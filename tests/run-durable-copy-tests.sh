#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
swiftc "$task_root/ios/OpenCommander/DurableFileCopy.swift" \
    "$task_root/ios/OpenCommander/VolumeIdentity.swift" \
    "$task_root/ios/tests/DurableCopyTests/main.swift" -o "$task_output/durable-tests"
"$task_output/durable-tests"
