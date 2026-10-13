#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
swiftc "$task_root/ios/OpenCommander/CloudConnection.swift" "$task_root/ios/OpenCommanderMacBridge/CloudConfigurationLease.swift" "$task_root/ios/tests/CloudLeaseTests/main.swift" -o "$task_output/lease-tests"
"$task_output/lease-tests"
