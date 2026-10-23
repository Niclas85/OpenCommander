#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d -t opencommander-remote-tests)
trap 'rm -rf "$task_output"' EXIT HUP INT TERM
cd "$task_root"
task_python=""
if [ "$#" -gt 1 ]; then
    echo "Usage: sh tests/run-remote-tests.sh [--live | /absolute/path/to/python]" >&2
    exit 2
fi
if [ "${1-}" = "--live" ]; then
    python3 -m venv "$task_output/venv"
    task_python="$task_output/venv/bin/python"
    "$task_python" -m pip install -r ios/tests/RemoteTests/requirements.txt
elif [ "$#" -eq 1 ]; then
    task_python="$1"
fi
if [ -n "$task_python" ]; then
    # Fail clearly before creating pipes/servers if a cleaned temporary Python
    # environment no longer contains the loopback fixture dependencies.
    "$task_python" -c 'import paramiko, pyftpdlib, OpenSSL, cryptography'
fi
xcrun --sdk macosx clang -Os -Wall -Wextra -Werror ios/OpenCommanderMacBridge/SSHAskPass.c -o "$task_output/OpenCommanderSSHAskPass"
xcrun swiftc -parse-as-library -DREMOTE_TRANSPORT_TESTS \
    ios/OpenCommander/CloudConnection.swift \
    ios/OpenCommander/Localization.swift \
    ios/OpenCommander/FileOperationSafety.swift \
    ios/OpenCommander/PublicCloudOAuth.swift \
    ios/OpenCommanderMacBridge/CloudConfigurationLease.swift \
    ios/OpenCommander/VolumeIdentity.swift \
    ios/OpenCommanderMacBridge/RcloneRuntime.swift \
    ios/OpenCommander/SharedDirectoryReads.swift \
    ios/OpenCommander/RemoteConnection.swift \
    ios/OpenCommander/DesktopBridgeProtocol.swift \
    ios/OpenCommanderMacBridge/DesktopBridge.swift \
    ios/OpenCommanderMacBridge/NTFSExtensionRegistration.swift \
    ios/OpenCommanderMacBridge/NTFSAccessPolicy.swift \
    ios/OpenCommanderMacBridge/NTFSAutoMount.swift \
    ios/OpenCommander/OneDriveClient.swift \
    ios/OpenCommander/RemoteFileClient.swift \
    ios/tests/RemoteTests/RemoteTests.swift -o "$task_output/remote-tests"
if [ -n "$task_python" ]; then
    "$task_output/remote-tests" "$task_python" "$task_output/fixture" "$task_output/OpenCommanderSSHAskPass"
else
    "$task_output/remote-tests"
fi
