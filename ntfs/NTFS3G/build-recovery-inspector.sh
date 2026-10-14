#!/bin/sh
# Pinned GPL source, read-only laboratory entry point. No installer or app update.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sh "$task_root/build-engine.sh"
task_source="$task_root/.build-native/ntfs-3g-2026.7.7"
task_build="$task_root/.build-native/recovery-inspector-build"
mkdir -p "$task_build"
patch -s -F 0 -o "$task_build/ntfsrecover.c" "$task_source/ntfsprogs/ntfsrecover.c" "$task_root/recovery-parser.patch"
clang -O2 -g -mmacosx-version-min=15.4 -DHAVE_CONFIG_H -Dmain=nk_upstream_recovery_main \
    -I"$task_source" -I"$task_source/include" -I"$task_source/include/ntfs-3g" -I"$task_source/ntfsprogs" \
    -c "$task_build/ntfsrecover.c" -o "$task_build/ntfsrecover-readonly-entry.o"
clang -O2 -g -mmacosx-version-min=15.4 -DHAVE_CONFIG_H \
    -I"$task_source" -I"$task_source/include" -I"$task_source/include/ntfs-3g" -I"$task_root/bridge" \
    "$task_root/tests/recovery_inspector.c" "$task_root/bridge/ntfs_bridge.c" "$task_source/ntfsprogs/playlog.c" \
    "$task_source/ntfsprogs/utils.c" "$task_build/ntfsrecover-readonly-entry.o" \
    "$task_source/libntfs-3g/.libs/libntfs-3g.a" -framework CoreFoundation \
    -o "$task_root/.build-native/recovery-inspector"
