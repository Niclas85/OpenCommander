#!/bin/sh
# Sign a COPY of the full Release app. Never strip NTFS or alter installed apps.
set -eu
test "$#" = 5 || { echo 'Usage: sign-macos-ntfs-release.sh source.app new-output-dir identity host-profile ntfs-profile' >&2; exit 2; }
task_source=$1
task_output=$2
task_identity=$3
task_host_profile=$4
task_module_profile=$5
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$task_source" in /*/OpenCommander.app) ;; *) exit 2 ;; esac
case "$task_output" in /*) ;; *) exit 2 ;; esac
test -d "$task_source" && test ! -L "$task_source" && test ! -e "$task_output"
test ! -e "$task_source/Contents/MacOS/OpenCommander.debug.dylib"
# Read metadata only; no profile contents or private key data are printed.
python3 - "$task_root" "$task_host_profile" "$task_module_profile" "$task_identity" <<'PY'
import sys, subprocess, plistlib, importlib.util, hashlib
root, host, module, identity = sys.argv[1:]
spec=importlib.util.spec_from_file_location('gate',root+'/scripts/check-macos-ntfs-distribution.py')
gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
for path,identifier,fskit in [(host,'com.github.niklaus85.OpenCommander',False),(module,'com.github.niklaus85.OpenCommander.NTFSModuleV2',True)]:
    p=plistlib.loads(subprocess.check_output(['/usr/bin/security','cms','-D','-i',path],stderr=subprocess.DEVNULL))
    gate.check_profile(p,identifier,'WB497999XX',fskit)
    gate.require(any(hashlib.sha1(c).hexdigest().upper()==identity for c in p.get('DeveloperCertificates',[])), 'Signing identity is not authorized by distribution profile')
print('PASS both real distribution profiles authorize exact app IDs and selected certificate')
PY
mkdir -p "$task_output"
task_app="$task_output/OpenCommander.app"
ditto "$task_source" "$task_app"
test "$(plutil -extract CFBundleIdentifier raw -o - "$task_app/Contents/Info.plist")" = com.github.niklaus85.OpenCommander
task_extension="$task_app/Contents/Extensions/OpenCommanderNTFSModule.appex"
test "$(plutil -extract CFBundleIdentifier raw -o - "$task_extension/Contents/Info.plist")" = com.github.niklaus85.OpenCommander.NTFSModuleV2
test "$(plutil -extract OpenCommanderNTFSWriteCondition raw -o - "$task_extension/Contents/Info.plist")" = OPENCOMMANDER_NTFS3G_EXPERIMENTAL
cp "$task_host_profile" "$task_app/Contents/embedded.provisionprofile"
cp "$task_module_profile" "$task_extension/Contents/embedded.provisionprofile"
python3 - "$task_output" <<'PY'
import sys,plistlib,pathlib
root=pathlib.Path(sys.argv[1]);team='WB497999XX'
for name,identifier,module in [('Host','com.github.niklaus85.OpenCommander',False),('Module','com.github.niklaus85.OpenCommander.NTFSModuleV2',True)]:
    # Native FSKit profiles authorize com.apple.application-identifier only.
    # A Catalyst-only application-identifier on the module passes notarization
    # but taskgated rejects it at launch as an unsatisfied entitlement.
    p={'com.apple.application-identifier':team+'.'+identifier,'com.apple.developer.team-identifier':team}
    if module: p.update({'com.apple.security.app-sandbox':True,'com.apple.developer.fskit.fsmodule':True})
    else: p.update({'application-identifier':team+'.'+identifier,'keychain-access-groups':[team+'.'+identifier]})
    (root/(name+'.entitlements.plist')).write_bytes(plistlib.dumps(p))
PY
for task_binary in OpenCommanderCloudArguments OpenCommanderSSHAskPass OpenCommanderNTFSAccess; do
    task_identifier=$task_binary
    if test "$task_binary" = OpenCommanderNTFSAccess; then task_identifier=com.github.niklaus85.OpenCommander.NTFSAccess; fi
    test -x "$task_app/Contents/MacOS/$task_binary"
    codesign --force --sign "$task_identity" --identifier "$task_identifier" --options runtime --timestamp "$task_app/Contents/MacOS/$task_binary"
done
test -f "$task_app/Contents/Library/LaunchDaemons/com.github.niklaus85.OpenCommander.NTFSAccess.plist"
codesign --force --sign "$task_identity" --options runtime --timestamp "$task_app/Contents/PlugIns/OpenCommanderMacBridge.bundle"
codesign --force --sign "$task_identity" --options runtime --timestamp --entitlements "$task_output/Module.entitlements.plist" "$task_extension"
codesign --force --sign "$task_identity" --options runtime --timestamp --entitlements "$task_output/Host.entitlements.plist" "$task_app"
codesign --verify --deep --strict "$task_app"
xcrun swift "$task_root/ntfs/NTFS3G/tests/signature_preflight.swift" "$task_extension"
ditto -c -k --sequesterRsrc --keepParent "$task_app" "$task_output/OpenCommander-NTFS-notarization.zip"
echo "SIGNED_FULL_NTFS_APP $task_app"
echo 'Not notarized yet. Submit, staple, then run check-macos-ntfs-distribution.py before public packaging.'
