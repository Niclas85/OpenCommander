#!/bin/sh
# Install the already signed normal-host build, retaining a recoverable backup.
# Move the product so its filesystem identity follows it into Applications and
# no second executable app remains in DerivedData for LaunchServices to discover.
set -eu
test "$#" = 0 || { echo "Usage: sh install-experimental-app.sh" >&2; exit 1; }
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
task_source="$task_root/ntfs/NTFS3G/.build-native/experimental-app/Build/Products/Debug-maccatalyst/OpenCommander.app"
task_destination=/Applications/OpenCommander.app
test -d "$task_source" && test ! -L "$task_source" && test ! -L "$task_destination"
if pgrep -f '^/Applications/OpenCommander[.]app/Contents/MacOS/OpenCommander([[:space:]]|$)' >/dev/null; then
    echo "Quit OpenCommander normally before installing this build." >&2
    exit 1
fi
if /sbin/mount | grep -E '\(openntfs[^, )]*[, )]' >/dev/null; then
    echo "An OpenCommander NTFS volume is mounted. Eject it normally before updating." >&2
    exit 1
fi
test "$(plutil -extract CFBundleIdentifier raw -o - "$task_source/Contents/Info.plist")" = com.github.niklaus85.OpenCommander
codesign --verify --deep --strict "$task_source"
test -x "$task_source/Contents/MacOS/OpenCommanderCloudArguments"
codesign --verify --strict "$task_source/Contents/MacOS/OpenCommanderCloudArguments"
xcrun swift "$task_root/ntfs/NTFS3G/tests/signature_preflight.swift" \
    "$task_source/Contents/Extensions/OpenCommanderNTFSModule.appex"
task_backup=$(mktemp -d "$task_root/ntfs/NTFS3G/.build-native/App-before-install.XXXXXX")
if test -e "$task_destination"; then
    mv "$task_destination" "$task_backup/OpenCommander.saved"
fi
if ! mv "$task_source" "$task_destination"; then
    if test -d "$task_backup/OpenCommander.saved" && test ! -e "$task_destination"; then
        mv "$task_backup/OpenCommander.saved" "$task_destination"
    fi
    echo "Installation failed; previous app restored where possible. Backup: $task_backup" >&2
    exit 1
fi
codesign --verify --deep --strict "$task_destination"
echo "INSTALLED_APP $task_destination"
echo "PREVIOUS_APP $task_backup/OpenCommander.saved"
echo "Launch the installed app to refresh its extension registration. No disk was mounted and no approval was changed."
