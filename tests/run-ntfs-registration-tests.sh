#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
xcrun swiftc "$task_root/ios/OpenCommanderMacBridge/NTFSExtensionRegistration.swift" \
    "$task_root/ios/tests/NTFSRegistrationTests/main.swift" -o "$task_output/registration-tests"
"$task_output/registration-tests" "$@"
