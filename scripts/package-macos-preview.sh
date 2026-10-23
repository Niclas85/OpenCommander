#!/bin/sh
# Public GUI preview only: never export device-bound development profiles.
# The installed app and its approved filesystem extension are not changed.
set -eu
test "$#" = 3 || { echo 'Usage: package-macos-preview.sh /absolute/OpenCommander.app /new/output-directory signing-identity' >&2; exit 2; }
task_source=$1
task_output=$2
task_identity=$3
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$task_source" in /*/OpenCommander.app) ;; *) exit 2 ;; esac
case "$task_output" in /*) ;; *) exit 2 ;; esac
test -d "$task_source" && test ! -L "$task_source" && test ! -e "$task_output"
codesign --verify --deep --strict "$task_source"
test "$(plutil -extract CFBundleIdentifier raw -o - "$task_source/Contents/Info.plist")" = com.github.niklaus85.OpenCommander
mkdir -p "$task_output/Package" "$task_output/PRIVATE-not-for-upload"
task_app="$task_output/Package/OpenCommander.app"
ditto "$task_source" "$task_app"
# Move only known copied components aside. Keep exclusions outside Package.
for task_item in Contents/embedded.provisionprofile Contents/Extensions Contents/Library/LaunchDaemons Contents/MacOS/OpenCommanderNTFSAccess; do
    if test -e "$task_app/$task_item"; then
        task_name=$(basename "$task_item")
        mv "$task_app/$task_item" "$task_output/PRIVATE-not-for-upload/$task_name"
    fi
done
if find "$task_app" \( -name '*.provisionprofile' -o -name '*.mobileprovision' -o -name '*.appex' -o -name '*-oauth.json' -o -name 'rclone.conf' \) -print | rg .; then
    echo 'Unexpected profile, extension or account/publisher configuration; refuse packaging.' >&2
    exit 1
fi
task_empty="$task_root/scripts/preview-entitlements.plist"
# Clear development/keychain-group entitlements on this PUBLIC COPY ONLY.
find "$task_app/Contents/MacOS" -type f -print | while IFS= read -r task_binary; do
    if file -b "$task_binary" | rg -q 'Mach-O'; then
        codesign --force --sign "$task_identity" --options runtime --timestamp=none --entitlements "$task_empty" "$task_binary"
    fi
done
codesign --force --sign "$task_identity" --options runtime --timestamp=none --entitlements "$task_empty" \
    "$task_app/Contents/PlugIns/OpenCommanderMacBridge.bundle"
codesign --force --sign "$task_identity" --options runtime --timestamp=none --entitlements "$task_empty" "$task_app"
codesign --verify --deep --strict "$task_app"
cp "$task_root/docs/releases/macos-preview-2026-10-23.md" "$task_output/Package/README.md"
cp "$task_root/LICENSE" "$task_output/Package/LICENSE-OpenCommander.txt"
cp "$task_app/Contents/Resources/Zstandard-LICENSE.txt" "$task_output/Package/LICENSE-Zstandard.txt"
task_zip_license="$task_root/ntfs/NTFS3G/.build-native/experimental-app/SourcePackages/checkouts/ZIPFoundation/LICENSE"
test -f "$task_zip_license"
cp "$task_zip_license" "$task_output/Package/LICENSE-ZIPFoundation.txt"
git -C "$task_root" rev-parse HEAD > "$task_output/Package/SOURCE-COMMIT.txt"
ditto -c -k --sequesterRsrc --keepParent "$task_output/Package" "$task_output/OpenCommander-1.3-macos-arm64-preview-20261023.zip"
echo "PUBLIC_ZIP $task_output/OpenCommander-1.3-macos-arm64-preview-20261023.zip"
echo 'Private exclusions are NOT part of the ZIP. GUI preview excludes integrated NTFS writing.'
