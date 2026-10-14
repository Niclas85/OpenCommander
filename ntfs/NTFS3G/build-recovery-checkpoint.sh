#!/bin/sh
# Separate opt-in experiment. Does NOT enable any writes in recovery-overlay.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sh "$task_root/build-recovery-overlay.sh"
task_source="$task_root/.build-native/ntfs-3g-2026.7.7"
task_build="$task_root/.build-native/recovery-overlay-build"
for task_mode in normal injection; do
    task_define=
    task_name=recovery-checkpoint
    if test "$task_mode" = injection; then
        task_define='-DNK_CHECKPOINT_TESTS -fsanitize=address,undefined -fno-omit-frame-pointer'
        task_name=recovery-checkpoint-injection
    fi
    clang -O2 -g -mmacosx-version-min=15.4 -DHAVE_CONFIG_H -DNK_ENABLE_CHECKPOINT_APPLY $task_define \
        -I"$task_source" -I"$task_source/include" -I"$task_source/include/ntfs-3g" \
        "$task_root/tests/recovery_overlay.c" "$task_source/ntfsprogs/playlog.c" \
        "$task_source/ntfsprogs/utils.c" "$task_build/ntfsrecover-overlay-entry.o" \
        "$task_source/libntfs-3g/.libs/libntfs-3g.a" -framework CoreFoundation \
        -o "$task_build/$task_name.next"
    mv "$task_build/$task_name.next" "$task_root/.build-native/$task_name"
done
