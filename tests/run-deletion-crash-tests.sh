#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
swiftc "$task_root/ios/OpenCommander/DurableFileCopy.swift" \
    "$task_root/ios/OpenCommander/NASExclusiveCopy.swift" \
    "$task_root/ios/OpenCommander/VolumeIdentity.swift" \
    "$task_root/ios/OpenCommander/Localization.swift" \
    "$task_root/ios/OpenCommander/FileOperationSafety.swift" \
    "$task_root/ios/OpenCommander/DurableTreeTransfer.swift" \
    "$task_root/ios/OpenCommander/DurableTransferQueue.swift" \
    "$task_root/ios/tests/DeletionCrashTests/main.swift" -o "$task_output/deletion-crash-tests"
"$task_output/deletion-crash-tests"
