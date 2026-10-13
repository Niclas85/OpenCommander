#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
swiftc "$task_root/ios/OpenCommander/Localization.swift" \
    "$task_root/ios/OpenCommander/MacFileSystem.swift" \
    "$task_root/ios/tests/CloudStorageTests/main.swift" -o "$task_output/cloud-storage-tests"
"$task_output/cloud-storage-tests"
