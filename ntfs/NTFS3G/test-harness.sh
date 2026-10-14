#!/bin/sh
# No registration, mounting, disk images, permissions or service changes.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
task_expect() {
    task_expected="$1"
    shift
    if "$@"; then task_actual=0; else task_actual=$?; fi
    test "$task_actual" = "$task_expected" || {
        echo "FAIL harness: expected $task_expected, got $task_actual" >&2
        exit 1
    }
}
task_expect 64 xcrun swift "$task_root/tests/run_bounded.swift"
task_expect 64 xcrun swift "$task_root/tests/run_bounded.swift" 0 /usr/bin/true
task_expect 0 xcrun swift "$task_root/tests/run_bounded.swift" 5 /usr/bin/true
task_expect 1 xcrun swift "$task_root/tests/run_bounded.swift" 5 /usr/bin/false
task_expect 7 xcrun swift "$task_root/tests/run_bounded.swift" 5 /bin/sh -c 'exit 7'
task_expect 124 xcrun swift "$task_root/tests/run_bounded.swift" 1 /bin/sleep 10
task_expect 126 xcrun swift "$task_root/tests/run_bounded.swift" 5 /OpenCommander-no-such-test-executable
task_expect 7 xcrun swift "$task_root/tests/signature_preflight.swift" /usr/bin/true
task_expect 7 xcrun swift "$task_root/tests/signature_preflight.swift" --diagnostic /usr/bin/true
echo "PASS harness: argument guards, success/failure propagation, timeout, launch failure and wrong identity refusal"
