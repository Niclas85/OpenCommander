#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
xcrun --sdk macosx clang -Os -fobjc-arc -Wall -Wextra -Werror -framework Foundation \
    "$task_root/ios/OpenCommanderMacBridge/CloudArguments.m" -o "$task_output/cloud-arguments"
swiftc -DCLOUD_RUNTIME_TESTS "$task_root/ios/OpenCommander/CloudConnection.swift" "$task_root/ios/OpenCommanderMacBridge/RcloneRuntime.swift" "$task_root/ios/tests/CloudRuntimeTests/main.swift" -o "$task_output/cloud-runtime-tests"
OPENCOMMANDER_TEST_ARGUMENT_HELPER="$task_output/cloud-arguments" "$task_output/cloud-runtime-tests" "$@"
