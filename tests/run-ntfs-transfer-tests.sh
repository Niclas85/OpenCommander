#!/bin/sh
# Isolated image only. No sudo, personal disk or security-setting changes.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_output=$(mktemp -d /private/tmp/OpenCommander-NTFS-Queue-XXXXXX)
task_device=
task_status=0
task_cleanup() {
    task_status=$?
    if test -n "$task_device"; then hdiutil detach "$task_device" || exit 1; fi
    echo "Retained isolated fixture: $task_output"
    exit "$task_status"
}
trap task_cleanup EXIT
mkdir "$task_output/mount"
swiftc "$task_root/ios/OpenCommander/Localization.swift" \
    "$task_root/ios/OpenCommander/FileOperationSafety.swift" \
    "$task_root/ios/OpenCommander/DurableFileCopy.swift" \
    "$task_root/ios/OpenCommander/VolumeIdentity.swift" \
    "$task_root/ios/OpenCommander/DurableTreeTransfer.swift" \
    "$task_root/ios/tests/ExternalFilesystemTests/main.swift" -o "$task_output/transfer-tests"
"$task_root/ntfs/NTFS3G/.build-native/image-tests" "$task_output/test.ntfs" \
    "$task_root/ntfs/NTFS3G/.build-native/ntfs-3g-2026.7.7/ntfsprogs/mkntfs" --clean
task_device=$(hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage -plist "$task_output/test.ntfs" | plutil -extract system-entities.0.dev-entry raw -o - -)
case "$task_device" in /dev/disk[0-9]*) ;; *) echo "Unexpected device" >&2; exit 1;; esac
test "$(diskutil info -plist "$task_device" | plutil -extract VirtualOrPhysical raw -o - -)" = Virtual
test "$(diskutil info -plist "$task_device" | plutil -extract BusProtocol raw -o - -)" = "Disk Image"
test "$(diskutil info -plist "$task_device" | plutil -extract TotalSize raw -o - -)" = 67108864
/sbin/mount -F -t openntfs -o nosuid,nodev,noowners "$task_device" "$task_output/mount"
"$task_output/transfer-tests" "$task_output/mount"
hdiutil detach "$task_device"
task_device=
task_device=$(hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage -plist "$task_output/test.ntfs" | plutil -extract system-entities.0.dev-entry raw -o - -)
case "$task_device" in /dev/disk[0-9]*) ;; *) echo "Unexpected reopened device" >&2; exit 1;; esac
test "$(diskutil info -plist "$task_device" | plutil -extract VirtualOrPhysical raw -o - -)" = Virtual
test "$(diskutil info -plist "$task_device" | plutil -extract BusProtocol raw -o - -)" = "Disk Image"
test "$(diskutil info -plist "$task_device" | plutil -extract TotalSize raw -o - -)" = 67108864
/sbin/mount -F -t openntfs -o nosuid,nodev,noowners "$task_device" "$task_output/mount"
"$task_output/transfer-tests" "$task_output/mount" --resume
