# NTFS continuation after the user-approved Mac restart

## LATEST: permanent-helper automatic Elements mount + write PASS

2026-10-14 user confirmed native approval, then requested automatic test.
SMAppService service enabled. First attempt exposed argv[0] relative helper path
and empty-string MountPoint handling bugs; no file writes occurred. Restored
Apple read-only mount, fixed both (dyld _NSGetExecutablePath; shared isMounted),
added regression checks. Approved service unregistered via app, app normally
quit, fixed signed build14 installed (backup App-before-install.1Xig1V), then
registered via app again with retained OS consent: NO new password required.
Fixed installed build includes pending-approval UX fix as well.

Automatic mount PASS at 22:22:48 and again after normal app quit/relaunch at
22:23:32 local. New 4408-byte file fsync/read PASS; normal unmount and independent
Apple read-only reopen matched SHA256
0be852739ee7f57faf1abc416a0265f45129219cc4005cb49a0b2b9331a1ea08.
Retained folder: OpenCommander-Test-Automatik-69BF4656-577F-4A8C-A126-82FBF9C47439,
file Schreibtest-Grüsse.txt. Second auto-mount readback checksum also matches.
Final state: Elements WRITABLE via openntfs at
/Volumes/OpenCommander-005C1A70-98E8-48E6-8809-334901DC6E32, disk4s1 (re-resolve
before next use), raw root:operator 0640 restored, helper approved/registered,
app automation enabled. UI shows "Laufwerk: Elements" at the new stable location.
No existing files overwritten/deleted; no restart or new password prompt.
Tests/run-ntfs-access-tests.sh PASS, signed build/signature PASS, diffcheck PASS.
Hardware unplug/replug, forced crash/timeout restoration and multi-drive acceptance
remain untested. No claim of complete production readiness. No commit/push.

## CURRENT: build14 permanent helper setup awaits native password entry

User explicitly requested automatic writable NTFS with one administrator setup,
then confirmed permanent service approval ("Ja, ich bestätige die dauerhafte").
Implemented SMAppService helper + authenticated XPC + bounded independent raw
device lease worker + opt-in automount + Connections/NTFS settings UI.
See AUTOMATIC-WRITE.md for exact limits and risk. Installed signed build14 at
/Applications/OpenCommander.app; backup App-before-install.dEhRq6/OpenCommander.saved.
Registration requested from actual app; SMAppService returned EPERM but status
requiresApproval. A second setup click set preference true and opened Settings.
Clicked the exact OpenCommander background switch (one system-wide item) under
the user's explicit permanent approval. Native macOS password sheet is OPEN:
"Anmeldeobjekte ... Systemeinstellungen verändern", button "Einstellung verändern".
User must enter password; do not access credentials or bypass it. Last observed
sheet unchanged. No new auto-mount PASS yet; Elements remains read-only so far.

Next: after user finishes, observe switch ON, bring /Applications/OpenCommander.app
forward (not bundleID, multiple copies indexed) to trigger approved scan; inspect
NTFS settings status, helper/logs, exact Elements UUID and raw permissions. Test
only a new unique file then independent Apple readback; normal unmount only.
Current helper uses fixed /Volumes/OpenCommander-UUID path and validates USB NTFS
only; no arbitrary helper commands or dirty/recovery overrides. Service lifecycle,
reconnect and worker crash/timeout acceptance are still open.
Build14 source has one post-install UX fix: register() may throw EPERM while status
requiresApproval; source now opens Settings immediately in that case. Installed
build14 predates that small fix (full build/signature tests before it PASS).
Tests: tests/run-ntfs-access-tests.sh, registration tests, remote regression PASS.
Build log /tmp/opencommander-ntfs-build14-final.log. No commit/push/reboot.

## Latest: physical Elements write/read PASS after native admin approval

User requested the native administrator dialog and then the physical test.
Native Authorization Services approval succeeded. One-shot diagnostic helper
temporarily granted uid501 ownership of ONLY /dev/rdisk4s1 after UUID/size checks;
restored root:operator 0640 BEFORE file writes (verified). No installed helper.
Normal-user openntfs2 mount succeeded on current build13. Exclusively created
OpenCommander-Test-3DBEB470-1DE9-44BB-84FD-22B0C1DEFFC8/Schreibtest-Grüsse.txt,
wrote/fsynced/read 4408 bytes. Normal unmount and independent Apple read-only
reopen verified exact content and SHA256:
0be852739ee7f57faf1abc416a0265f45129219cc4005cb49a0b2b9331a1ea08.
Final /Volumes/Elements Apple NTFS read-only, raw 0:5:640. No existing file
overwritten/deleted. Test folder retained. Both helper/test processes exited0.
Evidence: .build-native/registration-repair13.jIVxHz/physical-elements-after-restart.log.
This is driver-level physical acceptance, not a new UI copy test or automatic
production mount flow. The earlier permission blocker below is resolved for
this explicitly authorized one-shot test only.

## Latest physical test authorization and blocker

User explicitly authorized reading/writing Elements after the two synthetic PASS
runs. Identity verified: partition 005C1A70-98E8-48E6-8809-334901DC6E32,
volume C448189C-C1C4-442A-BB43-ABE4E6E47C8E, external USB 5TB, current disk4s1.
Normal unmount succeeded; normal-user openntfs2 mounting failed at resource
probe with Permission denied. NO new physical file writes ran. The cleanup
first encountered an already-unmounted device; explicit diskutil mount readOnly
restored /Volumes/Elements, verified Apple ntfs/WritableVolume=false. Raw device
permissions remain root:operator 0640. sudo -n requires a password; no credentials
or permission bypass attempted. Admin authorization remains needed. Prepared
private test scripts live in .build-native/elements-authorized-readwrite.swift
and test-elements-authorized.sh; re-resolve/verify device IDs before any retry.

## Post-restart result: normal build 13 mounted tests PASS twice

User reported restart; kern.boottime verified 2026-10-14 21:58:34 local
(1792007914). Both NEW fixtures uLwHKI and m9cu0T passed test-fskit.sh:
normal installed NTFSModuleV2 mounted, exact-case/Unicode, read/write/copy,
rename/replace/delete/truncate/fsync and timestamp tests passed, then independent
Apple read-only reopen verified persisted bytes, timestamps and names. Both
detached normally. hdiutil info is empty; earlier held images are no longer
attached. Installed build13 and single registration UUID are unchanged.
Logs: .build-native/registration-repair13.jIVxHz/after-restart.log and
after-restart-repeat.log. The pre-restart startup blockade below is historical.
Elements remains Apple NTFS read-only, now disk4s1; no physical writes/remounts.
Production readiness, physical-drive acceptance and full Linux parity are NOT
implied by these isolated passes. No additional restart authorization remains.

## Current authorization: ONE normal restart approved

2026-10-14: user replied “ok, ich genemige” to the explicit request for one
normal Mac restart followed by synthetic NTFS testing. This supersedes the older
NO-restart restriction for this one restart only. Do not force-close unsaved work
or bypass login/authentication. Restart has not yet been verified as completed.
After reconnecting, verify boot time, installed build13 and V2 registration,
then run test-fskit.sh on a NEW synthetic image only. No physical Elements
writes/remounts are authorized by this restart approval. Re-resolve disk IDs;
do not delete backing files for any still-attached images. Preserve all backups.

LATEST (supersedes build 12 below): normal signed experimental **build 13** is
installed and starts. New `NTFSExtensionRegistration` runs from the actual host
at startup, validates signatures/team/entitlements and refreshes only a changed
installed build. `install-experimental-app.sh` MOVES the build product instead
of retaining a duplicate `.app` in DerivedData. Actual host refresh succeeded;
PlugInKit shows ONE installed V2 record, UUID91019C15-0C42-4B56-843F-2C8AF84DA567.
A normal app quit/relaunch leaves that UUID unchanged. Original panes retained.
Registration unit tests and installed read-only signature checks pass; remote
transport compile/parser suite also passes. Build and strict signatures pass.

The cached normal-module start is STILL BLOCKED: fresh VfmrBb image timed out45s;
after saving V2 OFF and ON in Settings, fresh7LMaXn also timed out45s. Both detached
normally. No V2 process starts; no mounted-write test ran. A prior attempt to
restore the old build reference (qYSoCt) likewise timed out and detached. That
temporary registration was removed again before the single-copy installation.
No reboot/logout, protected service reset, physical writes or permission changes.
Do not repeat these identical probes. A fresh OS/session is the next diagnostic
step, now authorized once by the user's latest approval recorded above.
Evidence: `.build-native/registration-repair13.jIVxHz/`.
Backups: App-before-registration13.cBALCF (build12), App-before-install.s5UDfe
(first build13 without eager startup). Two older held images A8Io8Z/WYFIqz remain.
No commit/push. Build product was moved; rebuilding recreates it when needed.

LATEST: signed normal-host experimental **build 12 / NTFSModuleV2** installed
at `/Applications/OpenCommander.app`; host visibly starts with original settings.
User explicitly approved `OpenCommander NTFS 2`; switch saved ON. Final new
fixture nKCEht timed out at 45s before mounted tests, then detached normally.
Normal V2 mounting is STILL BLOCKED. No more blind ID rotations/probe repeats.
Earlier two diagnostic mounted passes below do NOT certify this latest module.
First V2 error2/underlying5 referenced the build-product URL missing from LS.
LS/PlugInKit refresh, OFF/save, Settings quit/reopen, ON/save and build12 with
explicit source plug-in removal/re-add of installed module did not resolve it.
NO protected service reset/restart, no OS reboot/logout or security bypass.

Native improvements pass: four 100ns timestamps (validation/no-write refusals,
failure propagation), streamed directory cookies, upstream bitmap-bit resume
fix, five page sizes/200 names, read-error and reopen controls, arm64 and Rosetta.
Apple independent read-only reopen passes positive-epoch dates/data/names. Its
reader underflows pre-1970 fractional birth dates; do not count that as PASS.
Normal V2 live timestamp/pagination tests could not run because startup blocks.

Linux latest fetched: `a8839e0b191795c52729229d2aef31b9f8afee0c`; only Windows
publisher docs changed after the integrated application source `653690e`.
76 portable tests and 27 portable Qt cases pass. Upstream GitHub run38621972845
Linux job passes400 tests/package; this modified worktree has not run on Linux.
Experimental builder now disables build-copy LaunchServices registration, as
the diagnostic builder already did. This does NOT fix/prove existing V2 startup.
Mac cloud setup has sanitized Google failures/explicit client/restart handling.
Full parity remains OPEN (durable cloud resume/global locks/DnD/account gates).
Details: `docs/mac-linux-parity-2026-10-14.md`; evidence
`.build-native/continuation-20261014.boHcRd/`. No commit/push requested/performed.
Backups: App-before-v2.BGkCs7 (V1/build11) and App-before-v2-build12.3RrMLJ (V2/build11).
Held synthetic images: A8Io8Z/disk7 and WYFIqz/disk8 on latest inspection;
never delete backing files or reuse IDs blindly. Physical Elements untouched
this continuation. Seven old synthetic safety sets compressed with verified
SHA-256 and retained .gz copies to reclaim space; no backup/source/log removed.

### Earlier separate diagnostic success (historical, before V2 update)

Latest continuation: **fresh separate diagnostic mounted write/read PASS**.
After the user completed Xcode sign-in, the signed diagnostic builder succeeded
with profiles for both separate IDs. Installed separately at
`/Applications/OpenCommander NTFS Starttest.app`; normal app build 11 untouched.
User explicitly approved enabling the named diagnostic extension; Settings ON
was saved and independently reopened/verified. Default-folder-app prompt declined.
`test-fskit.sh --diagnostic` exit 0, NEW 64 MiB fixture `0ygTjm`: native tests,
mounted create/write/read/copy/replace/rename/delete/truncate/fsync and exact
case-preserving enumeration all passed. Apple's independent read-only reopen
passed, both mounts normally detached. No reboot/logout/service reset/bypass.
A second fresh fixture `dViHHa` passed the complete same sequence (exit 0),
including independent Apple readback and both normal detaches. Harness passed.
This is NOT proof the original extension ID or automatic mounting is fixed.
No new physical test is authorized by this separate-image diagnostic.
Elements remains Apple-read-only, exact partition UUID unchanged, raw `0:5:640`.
Evidence: `.build-native/fresh-registration-evidence.1bjjSO/`.
The older A8Io8Z image remains attached (disk7 on latest inspection); do not
delete backing file or reuse identifiers. Removed only reproducible generated
images in `safety-images.0cCgPj` to reclaim space, not backups/logs/source.

### Earlier preparation (superseded by successful signed diagnostic above)

The user approved the proposed fresh-registration diagnostic. Sources/scripts
are ready: separate host `com.github.niklaus85.OpenCommander.NTFSStartTest`, module
suffix `.NTFSModule`, short name `openntfsdiag`, display `OpenCommander NTFS Starttest`.
Signed build failed: Xcode has NO Apple Account and no profiles for these IDs.
Xcode Settings > Apple Accounts is open and empty. User was asked to use Add
Apple Account and reply when done. Never request a password or code in chat.
Unsigned compile-only build PASSED; it is NOT installed/registered/approved.
Do not run that unsigned product or use mismatched profiles. Production app
is still installed build 11. After user sign-in, run signed
`sh ntfs/NTFS3G/build-launch-diagnostic.sh`, install separately as
`/Applications/OpenCommander NTFS Starttest.app`, approve the named extension,
then `sh ntfs/NTFS3G/test-fskit.sh --diagnostic`. Normal tests still use normal IDs.
See README for logs/guards; no physical-drive test is authorized by this new
diagnostic step. Free disk space was down to ~2.3 GiB during the compile; avoid
more large fresh build directories, reuse the diagnostic build directory.
Durable signed-build failure, unsigned-compile and harness logs:
`.build-native/launch-diagnostic-evidence.DbZmD4/`.

The user explicitly forbids restarting the computer. Do not restart or log out,
and do not reset/kill protected services as a workaround. The extension is ON.
Latest installed app is now diagnostic build 11, with target-only Debug dylib
opt-out and an actual signed module executable. Signature/entitlements and
host launch pass, but a new fixture 2tzHJx still timed out at FSKit probing
before module execution. That new disk8 image detached normally. This was NOT
a successful driver fix; exact registration/launch root cause is unresolved.
Build 10 backup: `.build-native/App-before-direct.vbyZqa/OpenCommander.saved`.
Build and mount/system logs: `/tmp/opencommander-ntfs-direct-entry-*.log`.
Launch Services registration refresh and a normal Settings off/on cycle did
not recover module startup. Security.framework verifies the actual signature,
exact ID and required true sandbox/FSKit entitlements. A 30-second bounded
retry timed out; there is still no current mounted write PASS.

Own new 64 MiB test image A8Io8Z remains attached, NOT mounted, on disk7 because
macOS refuses normal and force detach as busy. Re-resolve the exact image path
using hdiutil info before any later cleanup; never delete an attached backing
file or reuse this device identifier for a physical operation. No system service
was killed/restarted. Elements is still Apple-read-only with root:operator 0640.
See README's no-restart section and logs for the bounded retry/cleanup failure.
New test tools add a read-only signature/entitlement preflight and bound only
the explicitly launched test mount child (not a daemon).
The harness regression suite and installed-module Security API check passed.
Durable logs: `.build-native/no-restart-evidence.oQKIEm/`.

## Reconnected-drive result: PASS (14 October 2026)

The following continuation is now complete: a new 64 MiB FSKit fixture passed
all mounted tests and independent Apple readback; the exact Elements partition
was identified again, inspected read-only (NTFS 3.1, flags 0x0080, clean valid
journal, no hibernation), then mounted with the installed OpenCommander module.
A new direct 169-byte file and a separate F5 copy in OpenCommander both passed
exact readback. After normal unmount, Apple's independent read-only NTFS driver
read both files with SHA-256
`8c24bc0576f3afbbe565ac0783effba4fe030fd7475b0630dc0c2ccb9c48170a`.
The disk is restored read-only at `/Volumes/Elements`, raw permissions 0:5:640.

The old verifier failure was a canonical-path mismatch: Foundation resolves
`/private/tmp` to `/tmp`. Canonicalizing both sides fixed it without relaxing
the exact device, mount root, filesystem type or write-access guards.

No checkpoint repair was repeated and no preexisting user file was selected as
a write target. Retained test folder: `OpenCommander-Test-20261014-glVW9S`.
Logs are copied alongside the metadata backup. Automatic writable remounting,
crash/power-loss safety and production release approval remain separate gates.
The directory-case display issue is now fixed with a tracked enumeration patch
and the proper FSKit case-preserving capability. A new native suite, mounted
FSKit fixture and independent Apple reopen passed exact names/case-only rename.
See README's latest continuation for evidence and logs.

Automatic matching is implemented only in the separate `--automount` developer
build. The automatic-image gate failed on macOS 15.6: Apple NTFS read-only was
selected. A later explicit control hit the per-user task-launch mismatch after
the app replacement. Do not enable automatic claiming or claim it works.
No device permissions, system security settings or user files were changed.

Final state: normal opt-in experimental build 10 (no automatic matching) is
installed and the app launches. The user approved re-enabling the existing
extension; its Settings switch is now ON, saved and independently rechecked.
A fresh `test-fskit.sh` fixture passed native tests, but failed during probing
with ExtensionKit error 2 / underlying 16 (claims sandbox entitlement absent).
The actual installed signed extension HAS app-sandbox=true and its strict deep
signature verification passes. Registration points to build 10 in Applications.
Do not remove sandbox requirements or treat this as a passed mount/write test.
Failed fixture wN1lAk was detached normally. Elements remains Apple-read-only,
root:operator 0640. A supported fresh login/session or normal restart needs
authorization; none has been performed in this continuation, nor an OS upgrade.
Durable copies of this turn's build/native/mounted/automatic/final-control logs:
`.build-native/case-automount-evidence.7y9IX1/`. The final recovery suite passed,
including ordinary rollback and refusal controls; this is not crash-safety proof.
The re-enabled attempt's `opencommander-ntfs-reenabled-fskit.log` and
`opencommander-ntfs-reenabled-system.log` are copied into the same evidence dir.

The user reported a restart; host uptime still indicated 29 days. Do not claim
a completed kernel reboot. The current per-user FSKit session nevertheless
launched the installed module successfully, with no service/security bypass.

## Prior recovery context (historical)

- Branch: `codex/mac-linux-parity`. Changes are saved locally, not committed/pushed.
- User explicitly approved the Mac restart after warning that remote access disconnects.
- Do not force-quit apps or discard unsaved work if normal restart is cancelled.
- Latest pre-restart check found no attached external physical drives. The previous
  `/dev/disk6s1` no longer exists. Never reuse that identifier without resolving
  partition UUID `005C1A70-98E8-48E6-8809-334901DC6E32` and checking geometry again.
- Elements checkpoint repair already succeeded: exactly two restart pages backed
  up/applied/flushed/read back. Physical file writes were still unverified at
  this earlier point; they are now covered by the result above.
- Metadata backup: `.build-native/Elements-checkpoint.S2F6Go/original-and-replacement.bin`.
- Updated signed experimental app is installed at `/Applications/OpenCommander.app`.
  The previous version is `.build-native/App-before-statfs.6kljdB/OpenCommander.saved`.
- Bitmap-statfs caching and required maximum file size are implemented and built.
  Native image, recovery, checkpoint rollback and refusal tests passed. The new
  live FSKit module could not launch due to a cached PID-0 instance. SIP prevented
  restarting the agent; no protection was bypassed or disabled.
- Completed continuation plan: first run a new virtual-image `test-fskit.sh` gate. Then resolve
  the actual external disk identity, inspect current flags/journal read-only,
  perform the authorized physical file create/write/readback, OpenCommander UI
  copy, normal unmount and independent Apple readback. Do not blindly reapply the
  checkpoint repair or rerun the old hard-coded physical scripts.
- Full history and safety limitations: `README.md`. Current session diagnostics
  are under `/private/tmp/OpenCommander-NTFS-Authorized-glVW9S`; some temporary
  files may not survive reboot. Core sources and backups are in the repository.
- Preserve unrelated `app/build.gradle` and `release/*.aab` changes.
