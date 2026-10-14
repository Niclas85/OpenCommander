#!/bin/sh
# Explicit developer build only. Does not install, approve or mount anything.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test "$#" -le 1 || { echo "Usage: sh build-experimental-app.sh [--automount|--fresh-registration]" >&2; exit 1; }
task_build="$task_root/ntfs/NTFS3G/.build-native/experimental-app"
task_plist="$task_root/ios/OpenCommanderNTFSModule/Info.plist"
task_module=com.github.niklaus85.OpenCommander.NTFSModule
task_short=openntfs
task_display='OpenCommander NTFS'
set -- "${1:-}"
task_mode="$1"
set --
case "$task_mode" in
    "") ;;
    --automount)
        task_build="$task_root/ntfs/NTFS3G/.build-native/experimental-automount-app"
        mkdir -p "$task_build"
        task_plist="$task_build/Automount-Info.plist"
        xcrun swift "$task_root/ntfs/NTFS3G/tests/make_automount_profile.swift" \
            "$task_root/ios/OpenCommanderNTFSModule/Info.plist" "$task_plist"
        ;;
    --fresh-registration)
        # Stable v2 identity in the NORMAL host, not the separate diagnostic.
        # Existing preferences/Keychain/folder grants keep the normal host ID.
        # Never rotate this ID per build or silently approve the new extension.
        task_module=com.github.niklaus85.OpenCommander.NTFSModuleV2
        task_short=openntfs2
        task_display='OpenCommander NTFS 2'
        set -- -allowProvisioningUpdates
        ;;
    *) echo "Usage: sh build-experimental-app.sh [--automount|--fresh-registration]" >&2; exit 1 ;;
esac
xcrun xcodebuild -project "$task_root/ios/OpenCommander.xcodeproj" \
    -scheme OpenCommander -configuration Debug \
    -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
    -derivedDataPath "$task_build" ONLY_ACTIVE_ARCH=YES \
    REGISTER_APP_WITH_LAUNCH_SERVICES=NO \
    OPENCOMMANDER_NTFS_INFO_PLIST="$task_plist" \
    OPENCOMMANDER_NTFS_BUNDLE_IDENTIFIER="$task_module" \
    OPENCOMMANDER_NTFS_SHORT_NAME="$task_short" \
    OPENCOMMANDER_NTFS_DISPLAY_NAME="$task_display" \
    OPENCOMMANDER_NTFS_WRITE_CONDITION=OPENCOMMANDER_NTFS3G_EXPERIMENTAL "$@" build
task_app="$task_build/Build/Products/Debug-maccatalyst/OpenCommander.app"
task_write_condition=$(/usr/libexec/PlistBuddy -c 'Print :OpenCommanderNTFSWriteCondition' \
    "$task_app/Contents/Extensions/OpenCommanderNTFSModule.appex/Contents/Info.plist")
test "$task_write_condition" = OPENCOMMANDER_NTFS3G_EXPERIMENTAL
task_extension_plist="$task_app/Contents/Extensions/OpenCommanderNTFSModule.appex/Contents/Info.plist"
test "$(plutil -extract CFBundleIdentifier raw -o - "$task_extension_plist")" = "$task_module"
test "$(plutil -extract EXAppExtensionAttributes.FSShortName raw -o - "$task_extension_plist")" = "$task_short"
if test "$task_mode" = --automount; then
    test "$(/usr/libexec/PlistBuddy -c 'Print :OpenCommanderNTFSAutomaticMounting' "$task_extension_plist")" = true
    test "$(/usr/libexec/PlistBuddy -c 'Print :EXAppExtensionAttributes:FSMediaTypes:Partitionless:FSProbeOrder' "$task_extension_plist")" = 3900
else
    test "$(plutil -extract EXAppExtensionAttributes.FSMediaTypes json -o - "$task_extension_plist")" = '{}'
    if /usr/libexec/PlistBuddy -c 'Print :OpenCommanderNTFSAutomaticMounting' "$task_extension_plist" >/dev/null 2>&1; then
        echo "Refusing an unexpected automatic-mount marker in the default prototype" >&2; exit 1
    fi
fi
codesign --verify --deep --strict "$task_app"
xcrun swift "$task_root/ntfs/NTFS3G/tests/signature_preflight.swift" \
    "$task_app/Contents/Extensions/OpenCommanderNTFSModule.appex"
echo "EXPERIMENTAL_APP $task_app"
echo "Not production-ready. Install explicitly, then run test-fskit.sh as the login user."
if test "$task_mode" != --automount; then
    echo "Quit the app, then run sh ntfs/NTFS3G/install-experimental-app.sh; launch /Applications/OpenCommander.app."
fi
if test "$task_mode" = --fresh-registration; then
    echo "Normal host, stable v2 module. Requires separate user approval of OpenCommander NTFS 2. No automatic claiming."
fi
