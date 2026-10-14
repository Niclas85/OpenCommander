#!/bin/sh
# Creates one NEW regular image and mounts ONLY that image read-only with Apple NTFS.
set -eu
test "$#" -eq 0 && test "$(id -u)" != 0 || { echo "Run without arguments as the login user" >&2; exit 1; }
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
task_available=$(df -Pk "$task_root" | awk 'END {print $4}')
case "$task_available" in ''|*[!0-9]*) exit 1 ;; esac
test "$task_available" -ge 524288 || { echo "Requires 512 MiB free space; no image created" >&2; exit 1; }
task_fixture=$(mktemp -d "$task_root/.build-native/engine-readback.XXXXXX")
sh "$task_root/test-engine.sh" --clean > "$task_fixture/native.log" 2>&1
cat "$task_fixture/native.log"
task_image=$(sed -n 's/^CLEAN_IMAGE //p' "$task_fixture/native.log")
case "$task_image" in "$task_root"/.build-native/test-images.*/test.ntfs) ;; *) echo "Unexpected native fixture" >&2; exit 1 ;; esac
test -f "$task_image" && test ! -L "$task_image" && test "$(stat -f %z "$task_image")" = 67108864
task_mount_root=$(mktemp -d /private/tmp/engine-fixture.XXXXXX)
task_mount="$task_mount_root/mount"
mkdir "$task_mount"
task_disk=""
task_cleanup() {
    task_status=$?
    if test -n "$task_disk" && ! hdiutil detach "$task_disk"; then
        echo "Could not detach ONLY synthetic test image: $task_image" >&2; exit 1
    fi
    exit "$task_status"
}
trap task_cleanup EXIT
task_disk=$(hdiutil attach -readonly -nobrowse -mountpoint "$task_mount" -imagekey diskimage-class=CRawDiskImage -plist "$task_image" |
    plutil -extract system-entities.0.dev-entry raw -o - -)
case "$task_disk" in /dev/disk[0-9]*) ;; *) echo "Unexpected image device" >&2; exit 1 ;; esac
test "$(diskutil info -plist "$task_disk" | plutil -extract VirtualOrPhysical raw -o - -)" = Virtual
test "$(diskutil info -plist "$task_disk" | plutil -extract BusProtocol raw -o - -)" = 'Disk Image'
test "$(diskutil info -plist "$task_disk" | plutil -extract IOKitSize raw -o - -)" = 67108864
xcrun swift "$task_root/tests/verify_engine_reopened.swift" "$task_mount"
