#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
swiftc "$task_root/ios/OpenCommander/CloudConnection.swift" "$task_root/ios/OpenCommander/PublicCloudOAuth.swift" "$task_root/ios/tests/CloudOAuthTests/main.swift" -o "$task_output/cloud-oauth-tests"
"$task_output/cloud-oauth-tests"
/usr/bin/python3 "$task_root/tests/test-mac-public-oauth.py"
