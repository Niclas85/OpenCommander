#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
clang -O2 -c "$task_root/ios/OpenCommander/ZstandardDecoder.c" -o "$task_output/zstd.o"
swiftc -D OPENCOMMANDER_ZSTD -import-objc-header "$task_root/ios/OpenCommander/ZstandardDecoder.h" \
    "$task_output/zstd.o" "$task_root/ios/OpenCommander/Localization.swift" \
    "$task_root/ios/OpenCommander/FileOperationSafety.swift" \
    "$task_root/ios/tests/FileOperationSafetyTests/main.swift" -o "$task_output/safety-tests"
"$task_output/safety-tests"
