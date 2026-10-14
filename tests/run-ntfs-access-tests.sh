#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_dir=$(mktemp -d -t opencommander-access-tests)
xcrun swiftc "$task_root/ios/OpenCommanderMacBridge/NTFSAccessPolicy.swift" \
    "$task_root/ios/tests/NTFSAccessTests/main.swift" -o "$task_dir/tests"
"$task_dir/tests"
xcrun swiftc "$task_root/ios/OpenCommanderMacBridge/NTFSAccessPolicy.swift" \
    "$task_root/ios/NTFSAccessHelper/main.swift" -o "$task_dir/helper"
if "$task_dir/helper"; then echo 'FAIL: unprivileged helper accepted'; exit 1; fi
echo 'PASS privileged service refuses direct unprivileged execution'
xcrun swiftc -typecheck "$task_root/ios/OpenCommanderMacBridge/NTFSAccessPolicy.swift" \
    "$task_root/ios/OpenCommanderMacBridge/NTFSExtensionRegistration.swift" \
    "$task_root/ios/OpenCommanderMacBridge/NTFSAutoMount.swift"
