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
for task_phase in prepare resume reconcile download-prepare download-resume download-reconcile move-prepare move-rename move-resume receipt-prepare receipt-resume early-move-prepare early-move-upload early-move-retain early-move-undo early-download-prepare early-download-publish early-download-undo cross-prepare cross-fail cross-resume cross-undo; do
    OPENCOMMANDER_RESTART_ROOT="$task_restart" OPENCOMMANDER_RESTART_PHASE="$task_phase" \
        "$task_output/cloud-client-tests"
done
