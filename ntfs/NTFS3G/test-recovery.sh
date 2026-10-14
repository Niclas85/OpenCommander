#!/bin/sh
# Only fresh synthetic image files. Never repairs or mounts a physical volume.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$task_root/.build-native"
task_log=$(mktemp "$task_root/.build-native/recovery-safety.XXXXXX")
if sh "$task_root/test-safety.sh" > "$task_log" 2>&1; then
    sed -n '/^PASS /p' "$task_log"
else
    sed -n '1,160p' "$task_log"
    exit 1
fi
task_fixture=$(awk '/^RETAINED_FIXTURES / {print substr($0, 19)}' "$task_log")
case "$task_fixture" in "$task_root"/.build-native/safety-images.*) ;; *) echo 'Unexpected fixture directory' >&2; exit 1 ;; esac
sh "$task_root/build-recovery-inspector.sh"
task_inspector="$task_root/.build-native/recovery-inspector"
task_check() {
    task_image="$task_fixture/$1.ntfs"
    task_expected="$2"
    task_before=$(shasum -a 256 "$task_image")
    if task_message=$("$task_inspector" "$task_image" 2>&1); then task_status=0; else task_status=$?; fi
    if test "$task_status" != "$task_expected"; then
        printf '%s\n' "$task_message"
        echo "Unexpected inspector exit $task_status for $1" >&2
        exit 1
    fi
    test "$(shasum -a 256 "$task_image")" = "$task_before"
    echo "PASS recovery dry run $1: expected status $task_status, SHA-256 unchanged"
}
task_check base 0
task_check checkpoint-clean 0
# Deliberately incomplete synthetic transaction stream: the parser must refuse it,
# not claim recovery or clear the pending journal merely to allow a writable mount.
task_check unclean 1
task_check checkpoint-recoverable 0
task_check checkpoint-continuation 0
task_check continuation-invalid 1
task_check dirty 2
task_check windows-cache 2
task_check corrupt 2
task_check hibernated 2
ln -s "$task_fixture/base.ntfs" "$task_fixture/link.ntfs"
if "$task_inspector" "$task_fixture/link.ntfs"; then echo 'Unexpected symlink acceptance' >&2; exit 1; else test "$?" = 65; fi
if "$task_inspector" /dev/null; then echo 'Unexpected device acceptance' >&2; exit 1; else test "$?" = 65; fi
if "$task_inspector" --force "$task_fixture/base.ntfs"; then echo 'Unexpected extra option acceptance' >&2; exit 1; else test "$?" = 64; fi
echo 'PASS recovery inspector refuses symlinks, device nodes and caller-supplied recovery options'
sh "$task_root/build-recovery-overlay.sh"
task_inspector="$task_root/.build-native/recovery-overlay"
"$task_inspector" --self-test
task_check base 0
task_check checkpoint-clean 0
task_check unclean 2
task_check checkpoint-recoverable 0
task_check checkpoint-continuation 0
task_check continuation-invalid 2
task_proof=$("$task_inspector" "$task_fixture/checkpoint-recoverable.ntfs")
printf '%s\n' "$task_proof" | grep -q '^VIRTUAL_WRITE_READ_PROOF PASS:'
printf '%s\n' "$task_proof" | grep -q '^STAGING_VALIDATED:'
printf '%s\n' "$task_proof" | grep -q 'source_write_callbacks=0 applied=NO$'
echo 'PASS virtual checkpoint recovery and post-recovery create/write/read/delete, without source writes'
task_check dirty 2
task_check windows-cache 2
task_check corrupt 2
task_check hibernated 2
if "$task_inspector" "$task_fixture/link.ntfs"; then echo 'Unexpected overlay symlink acceptance' >&2; exit 1; else test "$?" = 65; fi
if "$task_inspector" /dev/null; then echo 'Unexpected overlay device-path acceptance' >&2; exit 1; else test "$?" = 65; fi
if "$task_inspector" --apply "$task_fixture/base.ntfs"; then echo 'Unexpected apply operation' >&2; exit 1; else test "$?" = 64; fi
if "$task_inspector" --source-fd 0 < /dev/null; then echo 'Unexpected non-disk descriptor acceptance' >&2; exit 1; else test "$?" = 68; fi
if "$task_inspector" --source-fd 0 <> "$task_fixture/base.ntfs"; then echo 'Unexpected writable backing descriptor acceptance' >&2; exit 1; else test "$?" = 66; fi
echo 'PASS overlay refuses symlink/device paths, apply options and non-disk descriptors'
sh "$task_root/test-checkpoint.sh" "$task_fixture"
echo "RETAINED_RECOVERY_FIXTURES $task_fixture"
