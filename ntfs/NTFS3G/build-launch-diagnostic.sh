#!/bin/sh
# A separate opt-in host/module identity and mount short name; no automatic media claiming.
# Does not install or approve the diagnostic. Ordinary app/settings remain separate.
set -eu
test "$#" -le 1 || { echo "Usage: build-launch-diagnostic.sh [--compile-only]" >&2; exit 1; }
case "${1:-}" in
    "") task_signing_argument=-allowProvisioningUpdates ;;
    --compile-only) task_signing_argument=CODE_SIGNING_ALLOWED=NO ;;
    *) echo "Usage: build-launch-diagnostic.sh [--compile-only]" >&2; exit 1 ;;
esac
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
task_build="$task_root/ntfs/NTFS3G/.build-native/launch-diagnostic-app"
mkdir -p "$task_build"
xcrun swift "$task_root/ntfs/NTFS3G/tests/make_diagnostic_host.swift" \
    "$task_root/ios/Info.plist" "$task_build/Host-Info.plist"
xcrun xcodebuild -project "$task_root/ios/OpenCommander.xcodeproj" \
    -scheme OpenCommander -configuration Debug \
    -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
    -derivedDataPath "$task_build" ONLY_ACTIVE_ARCH=YES \
    REGISTER_APP_WITH_LAUNCH_SERVICES=NO \
    OPENCOMMANDER_APP_INFO_PLIST="$task_build/Host-Info.plist" \
    OPENCOMMANDER_APP_BUNDLE_IDENTIFIER=com.github.niklaus85.OpenCommander.NTFSStartTest \
    OPENCOMMANDER_NTFS_DISPLAY_NAME='OpenCommander NTFS Starttest' \
    OPENCOMMANDER_NTFS_SHORT_NAME=openntfsdiag \
    OPENCOMMANDER_NTFS_WRITE_CONDITION=OPENCOMMANDER_NTFS3G_EXPERIMENTAL \
    CURRENT_PROJECT_VERSION=1 "$task_signing_argument" build
task_app="$task_build/Build/Products/Debug-maccatalyst/OpenCommander.app"
task_plist="$task_app/Contents/Extensions/OpenCommanderNTFSModule.appex/Contents/Info.plist"
test "$(plutil -extract CFBundleIdentifier raw -o - "$task_plist")" = com.github.niklaus85.OpenCommander.NTFSStartTest.NTFSModule
test "$(plutil -extract CFBundleIdentifier raw -o - "$task_app/Contents/Info.plist")" = com.github.niklaus85.OpenCommander.NTFSStartTest
test "$(plutil -extract OpenCommanderNTFSLaunchDiagnostic raw -o - "$task_app/Contents/Info.plist")" = true
test "$(plutil -extract CFBundleDisplayName raw -o - "$task_app/Contents/Info.plist")" = 'OpenCommander NTFS Starttest'
for task_key in CFBundleDocumentTypes CFBundleURLTypes; do
    if /usr/libexec/PlistBuddy -c "Print :$task_key" "$task_app/Contents/Info.plist" >/dev/null 2>&1; then
        echo "Refusing document/URL handlers in diagnostic host: $task_key" >&2
        exit 1
    fi
done
test "$(plutil -extract EXAppExtensionAttributes.FSShortName raw -o - "$task_plist")" = openntfsdiag
test "$(plutil -extract EXAppExtensionAttributes.FSMediaTypes json -o - "$task_plist")" = '{}'
test "$(plutil -extract OpenCommanderNTFSWriteCondition raw -o - "$task_plist")" = OPENCOMMANDER_NTFS3G_EXPERIMENTAL
if test "${1:-}" = --compile-only; then
    echo "UNSIGNED_DIAGNOSTIC_BUILD $task_app"
    echo "Compile evidence only. Do NOT install, register, launch or approve this unsigned product."
    exit 0
fi
codesign --verify --deep --strict "$task_app"
xcrun swift "$task_root/ntfs/NTFS3G/tests/signature_preflight.swift" --diagnostic \
    "$task_app/Contents/Extensions/OpenCommanderNTFSModule.appex"
echo "DIAGNOSTIC_APP $task_app"
echo "Install separately as /Applications/OpenCommander NTFS Starttest.app, then approve only the named diagnostic extension."
