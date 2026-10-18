#!/bin/sh
set -eu
test "${EFFECTIVE_PLATFORM_NAME:-}" = -maccatalyst || exit 0
task_output="$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/OpenCommanderNTFSAccess"
task_plists="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/LaunchDaemons"
mkdir -p "$(dirname "$task_output")" "$task_plists"
task_sdk=$(xcrun --sdk macosx --show-sdk-path)
task_temp=$(mktemp -d -t opencommander-ntfs-helper)
for task_arch in ${ARCHS:-arm64}; do
    case "$task_arch" in arm64|x86_64) ;; *) exit 1 ;; esac
    xcrun --sdk macosx swiftc -O -sdk "$task_sdk" -target "$task_arch-apple-macos13" \
        "$SRCROOT/OpenCommanderMacBridge/NTFSAccessPolicy.swift" "$SRCROOT/NTFSAccessHelper/main.swift" -o "$task_temp/$task_arch"
done
xcrun lipo -create "$task_temp"/* -output "$task_output"
cp "$SRCROOT/NTFSAccessHelper/com.github.niklaus85.OpenCommander.NTFSAccess.plist" "$task_plists/"
if test "${CODE_SIGNING_ALLOWED:-NO}" = YES; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --identifier com.github.niklaus85.OpenCommander.NTFSAccess --options runtime "$task_output"
fi
