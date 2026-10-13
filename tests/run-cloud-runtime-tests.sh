#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
swiftc -DCLOUD_RUNTIME_TESTS "$task_root/ios/OpenCommander/CloudConnection.swift" "$task_root/ios/OpenCommanderMacBridge/RcloneRuntime.swift" "$task_root/ios/tests/CloudRuntimeTests/main.swift" -o "$task_output/cloud-runtime-tests"
"$task_output/cloud-runtime-tests" "$@"
