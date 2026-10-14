# Continuation: Linux parity and NTFS, 14 October 2026

Post-restart update: user performed the approved restart; boot time verified.
Normal installed build13 V2 passed TWO complete synthetic mounted tests
(uLwHKI, m9cu0T), including read/write/copy/replace/rename/delete/truncate/fsync,
case/Unicode and timestamps, followed by independent Apple read-only persistence
verification. Both detached normally. Logs: NTFS `.build-native/registration-repair13.jIVxHz/after-restart{,-repeat}.log`.
Elements remains Apple NTFS read-only and untouched. The startup-blocked account
below is historical. This does not establish full parity or production readiness.

This is evidence of a partial continuation, **not complete parity or release
approval**. No reboot/logout, security-service reset, physical-drive write,
formatting, commit, push or release was performed in this continuation.

Latest NTFS follow-up: signed **build13** is installed. Startup now validates and
refreshes the installed extension once per changed build; the installer moves
the product into Applications and retains a recoverable `.saved` backup. The
actual startup refresh passed and only one V2 record remains; relaunch preserves
its UUID. Registration tests and remote parser/compile regression pass. Fresh
VfmrBb and7LMaXn mount attempts still time out before the module starts, including
after the approved V2 switch was saved OFF/ON. Both images detached normally.
The remaining OS startup state is unresolved; no normal-host write PASS or
permission to reboot is implied. Evidence: `registration-repair13.jIVxHz` under
the NTFS native build directory. The build12 account below is historical.

## Upstream source integration

Fetched `origin/codex/linux-desktop` again at
`a8839e0b191795c52729229d2aef31b9f8afee0c`. Its only change since
`653690e0c585c6a4ea664bd2d31acd1813e6702c` is Windows publisher documentation,
not application functionality. The integrated Linux source remains that of
`653690e`, ten commits after `9db1361`.
The changes under `linux/` are integrated, including the new conditional
Windows platform boundary used by the shared Linux desktop source. No Windows
native application/distribution was installed on the Mac. Existing Mac/Swift
work and Android release/build changes were preserved.

Eight changed upstream paths intentionally differ: cloud_config/cloud_listing
retain missing-runtime and authentication-priority safeguards; operations and
i18n retain verified-backup Undo checks/localization; ui and the three affected
test files retain earlier Mac-branch safety, explicit-language and compact-card
backports. All other upstream-changed Linux paths compare byte-for-byte.

The Linux CI configuration now includes archive/media/Qt dependencies, the
pinned checksum-verified cloud runtime and retained JUnit output. This workflow
has not been pushed/run for the current worktree. The unrelated Windows job
was not copied without its complete Windows distribution tree.

Read-only inspection of upstream GitHub run
[38621972845](https://github.com/Niclas85/OpenCommander/actions/runs/38621972845)
at `a8839e0` confirms the Linux job passed **400 tests** and built/uploaded its
package; the Apple job also passed. The overall run failed in Windows build and
Android SDK setup, not Linux. This verifies upstream, **not this unpushed modified
worktree**, its safety backports or the current native FSKit module.

## Native Mac cloud parity improvements

- Google setup distinguishes expired credentials, shared-application failures
  and quota errors without displaying backend responses or credential snippets.
  Authentication failures take precedence over quota text.
- Setup timeout explicitly requests a NEW sign-in/browser tab rather than
  suggesting retry of an expired callback. Requests outside setup retain their
  separate transient timeout behavior.
- Shared-Google-client selection is explicit; declining it opens complete custom
  registration fields rather than submitting empty defaults repeatedly.
- An explicitly selected custom client cannot silently fall back when fields
  are empty. Google requires both desktop ID and secret.
- Restart clears stale question/browser/device-code state and uses a NEW private
  configuration. Existing accounts/configurations are not overwritten.
- Native visible check: Google wizard in the current app shows German controls,
  rejects empty explicit client fields and reports that no account was saved.
  Cancel returned to the original iCloud/Downloads panes. No provider login or
  consent was submitted. A duplicate initial restart button was then removed.

## NTFS code improvements

- C/FSKit timestamp updates support access/modify/change/birth, retain 100ns
  precision, preserve unspecified fields and validate all requested dates before
  a combined resize can mutate contents. Read-only and system-file guards remain.
  Overflow/invalid dates cause zero device writes. Metadata write failures
  propagate; later explicit updates succeed.
- Directory enumeration streams directly to the FSKit packer instead of
  allocating every entry for each page. Mutation verifiers remain checked.
- New native-cookie tests exposed a pinned-engine bug: resumed enumeration
  started at bit zero rather than the cookie's bit within its bitmap byte.
  The final page could read an unallocated index block and fail with EIO.
  `directory-cookies.patch` corrects that offset only in generated native and
  both universal source copies, with zero fuzz; vendor archive unchanged.
- Directory conversion/metadata/read/close errors propagate instead of producing
  false empty/zero-size success. Early-stop callbacks stop real enumeration.
- Native regressions pass 1/2/7/13/31-entry pages over 200 unique original-case
  names, EOF, invalid-cookie zero-I/O refusal, injected read failure and reopen.
  Updated arm64 and x86_64/Rosetta engine tests passed.
- New `test-engine-readback.sh` creates only a new synthetic image, verifies its
  virtual identity/geometry, mounts read-only with Apple NTFS, checks exact file
  data/names and positive-epoch 100ns modify/birth dates, and detaches normally.
  **Known independent-reader limitation:** Apple's macOS 15.6 reader underflows
  the synthetic pre-1970 birth date (-1s + 234567800ns) to
  1844674407370s + 189729400ns. Native reopen reads the correct stored value;
  independent Apple verification of negative-epoch birth dates is NOT passed.

## Normal app integration and remaining FSKit gate

Signed experimental normal-host build **12** is installed at
`/Applications/OpenCommander.app` and visibly starts with original locations and
preferences. The opt-in `--fresh-registration` builder uses fixed module ID
`com.github.niklaus85.OpenCommander.NTFSModuleV2`, short name `openntfs2`, display
`OpenCommander NTFS 2`. It does NOT replace the normal host ID or claim media
automatically. Release/default builds remain fail-closed. Do not rotate module
IDs per build as a supposed permanent registry fix.

The user explicitly approved NTFS 2 activation; its Settings switch was saved ON.
The first mount failed before engine execution: ExtensionKit error 2/underlying
5 referenced the **build product path missing from Launch Services**, despite
PlugInKit reporting the installed Applications path. Supported registration
refresh plus ordinary Settings off/on did not resolve the next bounded probe;
it timed out, and new fixture WYFIqz remained busy/unmounted on disk8. After
saving OFF, quitting/reopening only Settings, and saving ON, another new fixture
jRazR7 also timed out but detached normally. No system service was restarted.

Build 12 was then signature-verified and installed with the build-product plug-in
explicitly removed from PlugInKit before unregistering its containing app;
only the installed extension was added again. A final new-image control is
recorded in `opencommander-ntfs-normal-v2-build12-mounted.log`; consult its actual
result, never infer success from the switch or successful compilation.
Final result: new fixture `nKCEht` timed out at 45 seconds before mounted writes;
it detached normally. Updated normal V2 remains blocked. Do not repeat the same
probe or rotate identities indefinitely. Updated timestamps/pagination compile
but are not live-mounted verified. No claim of a production-ready NTFS writer.

The experimental builder now sets `REGISTER_APP_WITH_LAUNCH_SERVICES=NO`, like
the separate diagnostic builder, to avoid registering its temporary build copy.
Shell syntax and non-mutating harness checks pass. This is prevention for future
builds, not proof of repairing the existing cached launch instance. Read-only
preflight still finds only the installed V2 PlugInKit path while FSClient omits
it; another mount was deliberately not repeated.

Backups: `.build-native/App-before-v2.BGkCs7/OpenCommander.saved` (original host
build 11/V1); `.build-native/App-before-v2-build12.3RrMLJ/OpenCommander.saved`
(first V2 build 11). Separate diagnostic app remains installed/enabled; its two
earlier successful mounted tests do not verify the updated normal V2 module.

Old held synthetic images A8Io8Z and WYFIqz must not be deleted while attached.
Resolve exact image paths before cleanup; never reuse a disk number blindly.
Elements remains untouched in this continuation; no new physical mount/write
or permission change is authorized by the synthetic tests.

## Verification completed here

- Signed Mac Catalyst arm64 normal-host/module build 12 and strict/deep signature.
- Native arm64 and x86_64/Rosetta engine metadata/pagination regression.
- Independent Apple NTFS positive-epoch metadata/data/name reopen, normal detach.
- Portable Linux cloud/OAuth/config/protocol/package/Undo subset: **76 passed**.
  Initial missing-rclone fixture failure resolved by exposing the existing
  verified private runtime in the test process only, not a global install.
- Portable Qt cloud-auth/transfer-details subset: **27 passed, 121 deselected**.
  An additional copy-progress case needs Linux `/proc/self/mountinfo` and is not
  claimed as a Mac-host Linux transfer acceptance test. Native Swift copying is
  tested separately. The upstream real-Linux CI result is recorded above;
  this modified worktree has not run on a Linux host.
- Swift cloud client, runtime, OAuth, OneDrive, durable copy/tree/queue and file
  safety suites passed. Harness identity/timeout guards and duplicate-key checks
  passed. No personal provider account was used by automated fixtures.

Logs: `ntfs/NTFS3G/.build-native/continuation-20261014.boHcRd/`.
Private Python 3.12.14 environment:
`/private/tmp/OpenCommander-LinuxLatest-20261014.naoIZq/modern` (pinned pytest
9.1.1, PySide6 6.11.2, libarchive-c 5.3). The first Python 3.9 environment could
not satisfy these pins and is not the tested runtime.

Disk-space handling: seven old generated safety-image sets were gzip-compressed,
each decompression compared with the original SHA-256 before removing only the
uncompressed generated copy. `.gz` files remain recoverable in those directories.
No source, personal file, attached image or Elements metadata backup was removed.
Earlier deletion of safety-images.0cCgPj belongs to the preceding continuation.

Full parity is still open: durable direct-cloud restart/checkpoints and legacy
staging adoption, global all-window/backend reservations, remaining Google-native
export/cache lifecycle and provider sharing, all native external DnD permutations,
complete illustrated/help interaction acceptance, real provider account acceptance,
automatic NTFS mounting/physical authorization, open-unlink/links/ACL/xattrs and
crash/power-loss gates. This work does not make those untested features complete.
