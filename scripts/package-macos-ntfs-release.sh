#!/bin/sh
# Package only a fully validated, notarized app; never alter its signature.
set -eu
test "$#" = 2 || { echo 'Usage: package-macos-ntfs-release.sh /absolute/OpenCommander.app /new/output-directory' >&2; exit 2; }
task_app=$1
task_output=$2
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$task_app" in /*/OpenCommander.app) ;; *) exit 2 ;; esac
case "$task_output" in /*) ;; *) exit 2 ;; esac
test ! -e "$task_output"
test -z "$(git -C "$task_root" status --porcelain)"
python3 "$task_root/scripts/check-macos-ntfs-distribution.py" "$task_app"
if find "$task_app" \( -name '*.p8' -o -name '*.p12' -o -name '*-oauth.json' -o -name 'rclone.conf' -o -name 'AuthKey_*' \) -print | rg .; then
    echo 'Publisher/account configuration found; refusing public packaging.' >&2
    exit 1
fi
mkdir -p "$task_output/Package"
ditto "$task_app" "$task_output/Package/OpenCommander.app"
cp "$task_root/docs/releases/macos-ntfs-2026-10-23.md" "$task_output/Package/README.md"
cp "$task_root/LICENSE" "$task_output/Package/LICENSE-OpenCommander.txt"
cp "$task_root/ntfs/NTFS3G/COPYING" "$task_output/Package/LICENSE-NTFS-GPL.txt"
cp "$task_root/ntfs/NTFS3G/THIRD-PARTY.md" "$task_output/Package/NTFS-THIRD-PARTY.md"
cp "$task_app/Contents/Resources/Zstandard-LICENSE.txt" "$task_output/Package/LICENSE-Zstandard.txt"
task_zip_license="$task_root/ntfs/NTFS3G/.build-native/experimental-app/SourcePackages/checkouts/ZIPFoundation/LICENSE"
test -f "$task_zip_license"
cp "$task_zip_license" "$task_output/Package/LICENSE-ZIPFoundation.txt"
git -C "$task_root" rev-parse HEAD > "$task_output/Package/SOURCE-COMMIT.txt"
task_commit=$(git -C "$task_root" rev-parse --short=7 HEAD)
git -C "$task_root" archive --format=zip --prefix=OpenCommander-source/ --output="$task_output/OpenCommander-$task_commit-ntfs-source.zip" HEAD
ditto -c -k --sequesterRsrc --keepParent "$task_output/Package" "$task_output/OpenCommander-1.3-macos-arm64-ntfs-20261023-r2.zip"
(cd "$task_output" && shasum -a 256 OpenCommander-1.3-macos-arm64-ntfs-20261023-r2.zip "OpenCommander-$task_commit-ntfs-source.zip" > SHA256SUMS-NTFS-20261023-r2.txt)
echo 'PASS full notarized NTFS package, corresponding source and checksums created'
