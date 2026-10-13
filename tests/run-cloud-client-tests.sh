#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
swiftc -parse-as-library "$task_root/ios/OpenCommander/CloudConnection.swift" \
    "$task_root/ios/OpenCommander/SharedDirectoryReads.swift" \
    "$task_root/ios/OpenCommander/OneDriveClient.swift" \
    "$task_root/ios/OpenCommander/RemoteConnection.swift" \
    "$task_root/ios/OpenCommander/RemoteFileClient.swift" \
    "$task_root/ios/OpenCommander/CloudFileClient.swift" \
    "$task_root/ios/tests/CloudClientTests/CloudClientTests.swift" -o "$task_output/cloud-client-tests"
"$task_output/cloud-client-tests"
