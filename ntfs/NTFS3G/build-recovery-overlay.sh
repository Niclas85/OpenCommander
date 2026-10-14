#!/bin/sh
# Laboratory-only replay sandbox: source fd read-only, writes to bounded RAM.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sh "$task_root/build-engine.sh"
task_source="$task_root/.build-native/ntfs-3g-2026.7.7"
task_build="$task_root/.build-native/recovery-overlay-build"
mkdir -p "$task_build"
# Patch a generated build copy only; the pinned vendor archive stays intact.
patch -s -F 0 -o "$task_build/ntfsrecover.c" "$task_source/ntfsprogs/ntfsrecover.c" "$task_root/recovery-parser.patch"
clang -O2 -g -mmacosx-version-min=15.4 -DHAVE_CONFIG_H \
    -Dmain=nk_overlay_recovery_main -Dntfs_mount=nk_overlay_mount -Dfopen=nk_overlay_fopen \
    -I"$task_source" -I"$task_source/include" -I"$task_source/include/ntfs-3g" -I"$task_source/ntfsprogs" \
    -c "$task_build/ntfsrecover.c" -o "$task_build/ntfsrecover-overlay-entry.o"
clang -O2 -g -mmacosx-version-min=15.4 -DHAVE_CONFIG_H \
    -I"$task_source" -I"$task_source/include" -I"$task_source/include/ntfs-3g" \
    "$task_root/tests/recovery_overlay.c" "$task_source/ntfsprogs/playlog.c" \
    "$task_source/ntfsprogs/utils.c" "$task_build/ntfsrecover-overlay-entry.o" \
    "$task_source/libntfs-3g/.libs/libntfs-3g.a" -framework CoreFoundation \
    -o "$task_build/recovery-overlay.next"
mv "$task_build/recovery-overlay.next" "$task_root/.build-native/recovery-overlay"
clang -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer -mmacosx-version-min=15.4 -DHAVE_CONFIG_H \
    -I"$task_build" -I"$task_source" -I"$task_source/include" -I"$task_source/include/ntfs-3g" -I"$task_source/ntfsprogs" \
    "$task_root/tests/recovery_parser_tests.c" "$task_source/ntfsprogs/playlog.c" "$task_source/ntfsprogs/utils.c" \
    "$task_source/libntfs-3g/.libs/libntfs-3g.a" -framework CoreFoundation \
    -o "$task_build/recovery-parser-tests"
"$task_build/recovery-parser-tests"
