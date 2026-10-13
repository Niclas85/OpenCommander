#!/bin/sh
# Both slices use the same verified source archive. Native image-test tools
# retain their separate build; Xcode links the universal engine archive.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
task_archive="$task_root/vendor/ntfs-3g_ntfsprogs-2026.7.7.tgz"
task_hash=d67b769025d32860549d35c2147e45024d172f81c540d750390ce3602c059dab
test "$(shasum -a 256 "$task_archive" | cut -d ' ' -f 1)" = "$task_hash"
sh "$task_root/build-engine.sh"
for task_arch in arm64 x86_64; do
    task_directory="$task_root/.build-native/universal-$task_arch"
    task_source="$task_directory/ntfs-3g-2026.7.7"
    mkdir -p "$task_directory"
    if [ ! -d "$task_source" ]; then tar -xzf "$task_archive" -C "$task_directory"; fi
    (
        cd "$task_source"
        if [ ! -f Makefile ]; then
            case "$task_arch" in arm64) task_host=aarch64-apple-darwin ;; x86_64) task_host=x86_64-apple-darwin ;; esac
            ./configure --build="$(sh config.guess)" --host="$task_host" \
                --disable-ntfs-3g --disable-shared --enable-static \
                --disable-crypto --disable-extras --disable-plugins \
                CC="xcrun --sdk macosx clang" \
                CFLAGS="-O2 -g -arch $task_arch -mmacosx-version-min=15.4"
        fi
        make -j4
        xcrun lipo libntfs-3g/.libs/libntfs-3g.a -verify_arch "$task_arch"
    )
done
task_output="$task_root/.build-native/libntfs-3g-universal.a"
task_temporary="$task_output.$$.tmp"
xcrun lipo -create \
    "$task_root/.build-native/universal-arm64/ntfs-3g-2026.7.7/libntfs-3g/.libs/libntfs-3g.a" \
    "$task_root/.build-native/universal-x86_64/ntfs-3g-2026.7.7/libntfs-3g/.libs/libntfs-3g.a" \
    -output "$task_temporary"
xcrun lipo "$task_temporary" -verify_arch arm64 x86_64
mv "$task_temporary" "$task_output"
