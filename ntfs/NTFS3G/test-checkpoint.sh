#!/bin/sh
# Uses only EXCLUSIVE COPIES of a previously generated synthetic fixture.
# No mount, raw-device path or privilege change is accepted here.
set -eu
umask 077
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test "$#" = 1
task_fixture=$(CDPATH= cd -- "$1" && pwd)
case "$task_fixture" in "$task_root"/.build-native/safety-images.*) ;; *) exit 64 ;; esac
test -f "$task_fixture/checkpoint-continuation.ntfs"
test ! -L "$task_fixture/checkpoint-continuation.ntfs"
sh "$task_root/build-recovery-checkpoint.sh"
sh "$task_root/build-recovery-inspector.sh"
task_work=$(mktemp -d "$task_root/.build-native/checkpoint-tests.XXXXXX")
task_binary="$task_root/.build-native/recovery-checkpoint"
task_original=$(shasum -a 256 "$task_fixture/checkpoint-continuation.ntfs" | awk '{print $1}')
task_image="$task_work/success.ntfs"
cp -n "$task_fixture/checkpoint-continuation.ntfs" "$task_image"
"$task_binary" --checkpoint-apply-fds 0 3 "$task_work/success.backup" < "$task_image" 3<> "$task_image"
test -s "$task_work/success.backup"
test "$(shasum -a 256 "$task_image" | awk '{print $1}')" != "$task_original"
"$task_root/.build-native/recovery-inspector" "$task_image" | grep -q '^ALREADY_CLEAN'
echo 'PASS checkpoint apply: exclusive durable backup, only mapped restart pages, clean reinspection'

task_image="$task_work/rollback.ntfs"
cp -n "$task_fixture/checkpoint-continuation.ntfs" "$task_image"
if NK_TEST_CHECKPOINT_FAIL_SECOND=1 "$task_root/.build-native/recovery-checkpoint-injection" \
    --checkpoint-apply-fds 0 3 "$task_work/rollback.backup" < "$task_image" 3<> "$task_image"; then exit 1; else test "$?" = 4; fi
test "$(shasum -a 256 "$task_image" | awk '{print $1}')" = "$task_original"
echo 'PASS checkpoint failure after first page: original full-image SHA-256 restored, backup retained'
if NK_TEST_CHECKPOINT_FAIL_FLUSH=1 "$task_root/.build-native/recovery-checkpoint-injection" \
    --checkpoint-apply-fds 0 3 "$task_work/flush-rollback.backup" < "$task_image" 3<> "$task_image"; then exit 1; else test "$?" = 4; fi
test "$(shasum -a 256 "$task_image" | awk '{print $1}')" = "$task_original"
echo 'PASS checkpoint flush failure after writing: exact original image restored'
if NK_TEST_CHECKPOINT_EXTRA_PAGE=1 "$task_root/.build-native/recovery-checkpoint-injection" \
    --checkpoint-apply-fds 0 3 "$task_work/extra-page.backup" < "$task_image" 3<> "$task_image"; then exit 1; else test "$?" = 4; fi
test ! -e "$task_work/extra-page.backup"
test "$(shasum -a 256 "$task_image" | awk '{print $1}')" = "$task_original"
echo 'PASS candidate containing any additional metadata page is rejected, with zero source changes'

task_image="$task_work/refuse.ntfs"
cp -n "$task_fixture/checkpoint-continuation.ntfs" "$task_image"
if "$task_binary" --checkpoint-apply-fds 0 3 "$task_work/missing/backup" < "$task_image" 3<> "$task_image"; then exit 1; else test "$?" = 4; fi
if "$task_binary" --checkpoint-apply-fds 0 3 "$task_work/success.backup" < "$task_image" 3<> "$task_image"; then exit 1; else test "$?" = 4; fi
if "$task_binary" --checkpoint-apply-fds 0 3 "$task_work/wrong.backup" < "$task_image" 3<> "$task_work/rollback.ntfs"; then exit 1; else test "$?" = 4; fi
test "$(shasum -a 256 "$task_image" | awk '{print $1}')" = "$task_original"
test "$(shasum -a 256 "$task_work/rollback.ntfs" | awk '{print $1}')" = "$task_original"
echo 'PASS checkpoint refuses missing/existing backup and mismatched output identity before writes'
test "$(shasum -a 256 "$task_fixture/checkpoint-continuation.ntfs" | awk '{print $1}')" = "$task_original"
echo "RETAINED_CHECKPOINT_FIXTURES $task_work"
