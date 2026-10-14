#!/bin/sh
# Developer gate: only creates/attaches a NEW image. Never accepts a user disk.
set -eu
test "$#" -eq 0 && test "$(id -u)" != 0 || { echo "Run without arguments as the login user" >&2; exit 1; }
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
xcrun swift "$task_root/tests/signature_preflight.swift" \
    /Applications/OpenCommander.app/Contents/Extensions/OpenCommanderNTFSModule.appex
xcrun swift "$task_root/tests/fskit_preflight.swift"
task_mode=$(/usr/libexec/PlistBuddy -c 'Print :OpenCommanderNTFSAutomaticMounting' \
    /Applications/OpenCommander.app/Contents/Extensions/OpenCommanderNTFSModule.appex/Contents/Info.plist)
test "$task_mode" = true || { echo "Requires the explicit --automount experimental build" >&2; exit 1; }
task_available=$(df -Pk "$task_root" | awk 'END {print $4}')
case "$task_available" in ''|*[!0-9]*) exit 1 ;; esac
test "$task_available" -ge 524288 || { echo "Requires 512 MiB free space" >&2; exit 1; }
sh "$task_root/test-engine.sh" --clean
task_fixture=$(mktemp -d "$task_root/.build-native/automount-fixture.XXXXXX")
task_image="$task_fixture/test.ntfs"
"$task_root/.build-native/image-tests" "$task_image" \
    "$task_root/.build-native/ntfs-3g-2026.7.7/ntfsprogs/mkntfs" --clean
task_mount_fixture=$(mktemp -d /private/tmp/fskit-fixture.XXXXXX)
task_mount="$task_mount_fixture/mount"
mkdir "$task_mount"
task_disk=""
task_cleanup() {
    task_status=$?
    if test -n "$task_disk" && ! hdiutil detach "$task_disk"; then
        echo "Could not detach ONLY test image: $task_image" >&2
        exit 1
    fi
    exit "$task_status"
}
trap task_cleanup EXIT
echo "Testing ordinary automatic mounting of ONLY new image $task_image (no mount -F, sudo or device permission changes)."
task_disk=$(hdiutil attach -nobrowse -mountpoint "$task_mount" \
    -imagekey diskimage-class=CRawDiskImage -plist "$task_image" |
    plutil -extract system-entities.0.dev-entry raw -o - -)
case "$task_disk" in /dev/disk[0-9]*) ;; *) echo "Unexpected test device" >&2; exit 1 ;; esac
test "$(diskutil info -plist "$task_disk" | plutil -extract VirtualOrPhysical raw -o - -)" = Virtual
test "$(diskutil info -plist "$task_disk" | plutil -extract BusProtocol raw -o - -)" = 'Disk Image'
test "$(diskutil info -plist "$task_disk" | plutil -extract IOKitSize raw -o - -)" = 67108864
if ! xcrun swift "$task_root/tests/automount_status.swift" "$task_mount" "$task_disk"; then
    echo "AUTOMOUNT_NOT_AVAILABLE: system did not select a writable OpenCommander NTFS mount. No mounted write test ran." >&2
    echo "Keep automatic claiming disabled in the installed app; do not work around this with global device permission changes." >&2
    exit 1
fi
xcrun swift "$task_root/tests/mounted_tests.swift" "$task_mount"
hdiutil detach "$task_disk"
task_disk=""
task_disk=$(hdiutil attach -readonly -nobrowse -mountpoint "$task_mount" \
    -imagekey diskimage-class=CRawDiskImage -plist "$task_image" |
    plutil -extract system-entities.0.dev-entry raw -o - -)
xcrun swift "$task_root/tests/verify_reopened.swift" "$task_mount"
echo "PASS automatic image mount and independent persistence check; physical-device authorization is a separate gate."
