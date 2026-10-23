#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
swiftc -parse-as-library "$task_root/ios/OpenCommander/CloudConnection.swift" \
    "$task_root/ios/OpenCommander/Localization.swift" \
    "$task_root/ios/OpenCommander/FileOperationSafety.swift" \
    "$task_root/ios/OpenCommander/SharedDirectoryReads.swift" \
    "$task_root/ios/OpenCommander/OneDriveClient.swift" \
    "$task_root/ios/OpenCommander/RemoteConnection.swift" \
    "$task_root/ios/OpenCommander/RemoteFileClient.swift" \
    "$task_root/ios/OpenCommander/CloudFileClient.swift" \
    "$task_root/ios/OpenCommander/OnlineUndo.swift" \
    "$task_root/ios/tests/CloudClientTests/CloudClientTests.swift" -o "$task_output/cloud-client-tests"
"$task_output/cloud-client-tests"
task_restart=$(mktemp -d /private/tmp/OpenCommander-CloudRestart-XXXXXX)
trap 'rm -rf "$task_output" "$task_restart"' EXIT HUP INT TERM
for task_phase in prepare resume reconcile download-prepare download-resume download-reconcile move-prepare move-rename move-resume receipt-prepare receipt-resume early-move-prepare early-move-upload early-move-retain early-move-undo early-download-prepare early-download-publish early-download-undo cross-prepare cross-fail cross-resume cross-undo replacement-move-prepare replacement-move-resume replacement-move-undo; do
    OPENCOMMANDER_RESTART_ROOT="$task_restart" OPENCOMMANDER_RESTART_PHASE="$task_phase" \
        "$task_output/cloud-client-tests"
done
for task_phase in cross-replace-prepare cross-replace-fail cross-replace-resume cross-replace-undo; do
    OPENCOMMANDER_RESTART_ROOT="$task_restart" OPENCOMMANDER_RESTART_PHASE="$task_phase" \
        "$task_output/cloud-client-tests"
done
for task_phase in replacement-undo-confirm cross-undo-confirm; do
    OPENCOMMANDER_RESTART_ROOT="$task_restart" OPENCOMMANDER_RESTART_PHASE="$task_phase" \
        "$task_output/cloud-client-tests"
done
# Kill the test child only, after its synthetic backend commits a rename but
# before acknowledging it. Each boundary uses a new isolated account/journal.
for task_replace in 0 1; do
    for task_boundary in publication retention; do
        task_kill_root=$(mktemp -d /private/tmp/OpenCommander-CloudRestart-XXXXXX)
        OPENCOMMANDER_RESTART_ROOT="$task_kill_root" OPENCOMMANDER_RESTART_PHASE=cross-kill-prepare \
            OPENCOMMANDER_KILL_REPLACE="$task_replace" "$task_output/cloud-client-tests"
        task_kill_status=0
        OPENCOMMANDER_RESTART_ROOT="$task_kill_root" OPENCOMMANDER_RESTART_PHASE=cross-kill-crash \
            OPENCOMMANDER_KILL_REPLACE="$task_replace" OPENCOMMANDER_KILL_BOUNDARY="$task_boundary" \
            "$task_output/cloud-client-tests" || task_kill_status=$?
        if [ "$task_kill_status" -ne 137 ]; then
            echo "FAIL expected SIGKILL (137), received $task_kill_status; fixture retained: $task_kill_root" >&2
            exit 1
        fi
        for task_phase in cross-kill-tamper cross-kill-resume cross-kill-undo; do
            OPENCOMMANDER_RESTART_ROOT="$task_kill_root" OPENCOMMANDER_RESTART_PHASE="$task_phase" \
                OPENCOMMANDER_KILL_REPLACE="$task_replace" "$task_output/cloud-client-tests"
        done
        # Only the exact freshly created disposable fixture is removed.
        rm -r "$task_kill_root"
    done
done
