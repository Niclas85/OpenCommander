#!/bin/sh
# Only generated copies of the pinned engine are patched, never vendor/.
set -eu
test "$#" -eq 1 || { echo "Expected generated engine source directory" >&2; exit 1; }
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
task_source=$(CDPATH= cd -- "$1" && pwd)
case "$task_source" in
    "$task_root"/.build-native/ntfs-3g-2026.7.7|"$task_root"/.build-native/universal-*/ntfs-3g-2026.7.7) ;;
    *) echo "Refusing to patch outside the generated engine builds" >&2; exit 1 ;;
esac
cd "$task_source"
for task_name in case-preserving-readdir.patch directory-cookies.patch; do
    task_patch="$task_root/$task_name"
    if patch --dry-run --batch --forward --fuzz=0 -p1 < "$task_patch" >/dev/null 2>&1; then
        patch --batch --forward --fuzz=0 -p1 < "$task_patch"
    elif patch --dry-run --batch --forward --fuzz=0 -R -p1 < "$task_patch" >/dev/null 2>&1; then
        : # Already applied; do not touch timestamps or force needless rebuilds.
    else
        echo "Engine patch does not match generated source; refusing to continue: $task_name" >&2
        exit 1
    fi
done
