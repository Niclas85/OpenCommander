#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d -t opencommander-image-tests)
task_cleanup() {
    rm -f "$task_output/image-tests"
    rmdir "$task_output"
}
trap task_cleanup EXIT HUP INT TERM
xcrun swiftc "$task_root/ios/OpenCommander/ImagePreviewLoader.swift" \
    "$task_root/ios/tests/ImagePreviewTests/main.swift" -o "$task_output/image-tests"
"$task_output/image-tests"
