#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_seconds=${1:-7200}
task_output=$(mktemp -d /private/tmp/OpenCommander-Endurance-Build-XXXXXX)
task_fixture=$(mktemp -d /private/tmp/OpenCommander-Endurance-XXXXXX)
echo "ENDURANCE_FIXTURE $task_fixture"
echo "ENDURANCE_BUILD $task_output"
swiftc -parse-as-library "$task_root/ios/OpenCommander/CloudConnection.swift" \
    "$task_root/ios/OpenCommander/Localization.swift" \
    "$task_root/ios/OpenCommander/FileOperationSafety.swift" \
    "$task_root/ios/OpenCommander/SharedDirectoryReads.swift" \
    "$task_root/ios/OpenCommander/OneDriveClient.swift" \
    "$task_root/ios/OpenCommander/RemoteConnection.swift" \
    "$task_root/ios/OpenCommander/RemoteFileClient.swift" \
    "$task_root/ios/OpenCommander/CloudFileClient.swift" \
    "$task_root/ios/OpenCommander/OnlineUndo.swift" \
    "$task_root/ios/tests/CloudClientTests/Endurance.swift" -o "$task_output/cloud-endurance-tests"
shasum -a 256 "$task_root/ios/OpenCommander/CloudConnection.swift" \
    "$task_root/ios/OpenCommander/Localization.swift" "$task_root/ios/OpenCommander/FileOperationSafety.swift" \
    "$task_root/ios/OpenCommander/SharedDirectoryReads.swift" "$task_root/ios/OpenCommander/RemoteConnection.swift" \
    "$task_root/ios/OpenCommander/CloudFileClient.swift" \
    "$task_root/ios/OpenCommander/RemoteFileClient.swift" "$task_root/ios/OpenCommander/OnlineUndo.swift" \
    "$task_root/ios/OpenCommander/OneDriveClient.swift" "$task_root/ios/tests/CloudClientTests/Endurance.swift"
/usr/bin/caffeinate -i "$task_output/cloud-endurance-tests" "$task_fixture" "$task_seconds"
