#!/bin/sh
# Creates only NEW regular image files; no user device, mount or privilege change.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sh "$task_root/build-engine.sh"
task_source="$task_root/.build-native/ntfs-3g-2026.7.7"
clang -Wall -Wextra -Werror -g -mmacosx-version-min=15.4 -DHAVE_CONFIG_H \
    -I"$task_source" -I"$task_source/include" -I"$task_source/include/ntfs-3g" \
    "$task_root/tests/safety_tests.c" "$task_source/libntfs-3g/.libs/libntfs-3g.a" \
    -framework CoreFoundation -o "$task_root/.build-native/safety-tests"
task_fixture=$(mktemp -d "$task_root/.build-native/safety-images.XXXXXX")
"$task_root/.build-native/safety-tests" "$task_fixture" "$task_source/ntfsprogs/mkntfs"
