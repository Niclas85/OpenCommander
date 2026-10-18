#!/bin/sh
# Explicit physical-volume acceptance: only empty OpenCommander-LiveQA-* folders.
set -eu
test "$#" -eq 2 || { echo 'Pass empty NAS fixture and empty Elements fixture directories.' >&2; exit 1; }
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
swiftc -D OPENCOMMANDER_NAS \
    "$task_root/ios/OpenCommander/Localization.swift" \
    "$task_root/ios/OpenCommander/FileOperationSafety.swift" \
    "$task_root/ios/OpenCommander/DurableFileCopy.swift" \
    "$task_root/ios/OpenCommander/VolumeIdentity.swift" \
    "$task_root/ios/OpenCommander/DurableTreeTransfer.swift" \
    "$task_root/ios/OpenCommander/NASExclusiveCopy.swift" \
    "$task_root/ios/tests/NASExclusiveCopyTests/main.swift" \
    -o "$task_output/nas-tests"
"$task_output/nas-tests" "$1" "$2"
