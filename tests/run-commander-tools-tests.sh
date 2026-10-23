#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
swiftc "$task_root/ios/OpenCommander/Localization.swift" \
    "$task_root/ios/OpenCommander/FileOperationSafety.swift" \
    "$task_root/ios/OpenCommander/CommanderTools.swift" \
    "$task_root/ios/tests/CommanderToolsTests/main.swift" -o "$task_output/tools-tests"
"$task_output/tools-tests"
swiftc "$task_root/ios/OpenCommander/Localization.swift" \
    "$task_root/ios/OpenCommander/FileOperationSafety.swift" \
    "$task_root/ios/OpenCommander/CommanderTools.swift" \
    "$task_root/ios/tests/RenameCrashTests/main.swift" -o "$task_output/rename-crash-tests"
for task_scenario in before after next source changed; do
    task_crash_root=$(mktemp -d /private/tmp/OpenCommander-RenameCrash-XXXXXX)
    "$task_output/rename-crash-tests" "$task_crash_root" prepare
    task_boundary=kill-after-move
    task_recovery=recover
    case "$task_scenario" in
        before) task_boundary=kill-before-move ;;
        next) task_boundary=kill-next-move ;;
        source) task_recovery=recover-source ;;
        changed) task_recovery=recover-changed ;;
    esac
    task_crash_status=0
    "$task_output/rename-crash-tests" "$task_crash_root" "$task_boundary" || task_crash_status=$?
    if [ "$task_crash_status" -ne 137 ]; then
        echo "FAIL expected SIGKILL 137, got $task_crash_status; fixture retained: $task_crash_root" >&2
        exit 1
    fi
    "$task_output/rename-crash-tests" "$task_crash_root" "$task_recovery"
    rm -r "$task_crash_root"
done
