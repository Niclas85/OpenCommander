#!/bin/sh
# Builds an isolated debug app and signs only its disposable local products.
# No Apple account/profile registration or production app installation is needed.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_build=$(mktemp -d /tmp/OpenCommander-MacUITests.XXXXXX)
task_id=com.github.niklaus85.OpenCommander.MacUITests
task_arch=$(uname -m)
case "$task_arch" in arm64|x86_64) ;; *) echo "Unsupported Mac architecture: $task_arch" >&2; exit 2 ;; esac
cd "$task_root"
xcodebuild build-for-testing -project ios/OpenCommander.xcodeproj -scheme OpenCommander \
    -destination "platform=macOS,variant=Mac Catalyst,arch=$task_arch" -derivedDataPath "$task_build" \
    OPENCOMMANDER_APP_BUNDLE_IDENTIFIER="$task_id" CODE_SIGNING_ALLOWED=NO
task_products="$task_build/Build/Products/Debug-maccatalyst"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$task_products/OpenCommander.app/Contents/Info.plist")" = "$task_id"
codesign --force --deep --sign - "$task_products/OpenCommander.app"
codesign --force --deep --sign - "$task_products/OpenCommanderUITests-Runner.app"
echo "UI test results are retained in $task_build/Logs/Test"
xcodebuild test-without-building -project ios/OpenCommander.xcodeproj -scheme OpenCommander \
    -destination "platform=macOS,variant=Mac Catalyst,arch=$task_arch" -derivedDataPath "$task_build" \
    -only-testing:OpenCommanderUITests/MacDesktopParityTests \
    OPENCOMMANDER_APP_BUNDLE_IDENTIFIER="$task_id" CODE_SIGNING_ALLOWED=NO
