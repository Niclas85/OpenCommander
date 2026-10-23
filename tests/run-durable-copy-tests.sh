#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
swiftc "$task_root/ios/OpenCommander/DurableFileCopy.swift" \
    "$task_root/ios/OpenCommander/VolumeIdentity.swift" \
    "$task_root/ios/tests/DurableCopyTests/main.swift" -o "$task_output/durable-tests"
"$task_output/durable-tests"
swiftc "$task_root/ios/OpenCommander/DurableFileCopy.swift" \
    "$task_root/ios/OpenCommander/VolumeIdentity.swift" \
    "$task_root/ios/tests/DurableCopyCrashTests/main.swift" -o "$task_output/crash-tests"
task_crash_root=$(mktemp -d /private/tmp/OpenCommander-DurableCrash-XXXXXX)
"$task_output/crash-tests" "$task_crash_root" prepare
task_crash_status=0
"$task_output/crash-tests" "$task_crash_root" crash || task_crash_status=$?
if [ "$task_crash_status" -ne 137 ]; then
    echo "FAIL expected SIGKILL (137), received $task_crash_status; fixture retained: $task_crash_root" >&2
    exit 1
fi
"$task_output/crash-tests" "$task_crash_root" resume
rm -r "$task_crash_root"
