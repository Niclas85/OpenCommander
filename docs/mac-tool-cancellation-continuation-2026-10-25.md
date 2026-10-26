# Cloud/Linux tool special cases — Build20, 25 October 2026

Scope: continue the existing Linux-parity ledger, excluding WebDAV. Personal
files, stored accounts and the existing uncommitted work are preserved. No OS
restart. Remote Linux branch head independently checked with ls-remote:
`codex/linux-desktop@e3b2981ad5a88551be81b86b6c6453e26e2e2ff5`, unchanged from
the acceptance reference. No branch switch/reset/merge was performed.

## Corrected cancellation boundaries

The native local tool worker checked cancellation during filesystem reads but
not when publishing its completed result on the main thread. Cancel between
those boundaries could publish comparison/search rows, or enable a rename plan,
despite the user having cancelled. Publication now rechecks the cancellation
token before exposing any result or plan. This concerns read-only search,
comparison and rename preview; it does not discard history for actual completed
renames, which retain their rollback/recovery handling.

Online tool transports can return cancellation as NSError rather than Swift's
CancellationError. Tool failure rendering now checks the owning stored Task and
thread-safe token as well as the error type. Task state is inspected on the main
thread, not read from a background filesystem worker; Task.isCancelled on the
plain dispatch callback would describe the wrong execution context.

## New bounded native evidence

Only the exact DEBUG UI-test bundle with the existing validated private test
root can use an opt-in post-read barrier. It waits at most20 seconds and writes
only its own readiness marker. Release builds exclude the barrier. This makes
the result/publication race reproducible without slowing or editing user files.

- First native attempt failed to initialize macOS automation mode before any
  test body ran. `/tmp/opencommander-b20-native-tools.log`. Not a passing test.
- Retry: real local search, compare and rename-preview sequences passed34.857s.
  Each run finished reading before Cancel; no results were published, Apply
  remained disabled, exact source bytes were unchanged, and a fresh retry
  produced normal results. Dialogs closed normally after completion.
- Real native cloud/local comparison with the existing synthetic cloud
  transport passed21.073s. Cancel was issued during its five-second download,
  the UI remained usable, reported cancellation, published no equality/rows,
  removed the owned download container and retained exact local source bytes.
  Retry produced an actual `Equal · Proof.txt` row. This is native UI with a
  synthetic transport, not a real-account/network-disconnection claim.
  `/tmp/opencommander-b20-native-tools-retry.log` and
  `.build-native/ui-20261025/Logs/Test/Test-OpenCommander-2026.10.25_11-26-55-+0100.xcresult`.
- `tests/run-commander-tools-tests.sh`:19 PASS groups after adding explicit
  cyclic-plan cases. Both counter-preview and a supplied two-sided cyclic plan
  refuse before any rename callback; both source byte arrays are identical
  afterward. Existing rename/journal crash tests include intentional SIGKILL
  of disposable child processes, not app failures. Log
  `/tmp/opencommander-b20-tools-final.log`.
- `tests/run-cloud-client-tests.sh`:86 PASS groups, including interrupted
  upload/download, replacement, cross-cloud moves, process restart, actual
  synthetic backend commit/acknowledgment kills, reconciliation and safe Undo.
  `/tmp/opencommander-b20-cloud-client.log`.

The full Linux/all-provider acceptance is still incomplete. In particular, the
new cyclic-plan check is a core test, not a native/provider-wide cycle matrix.
Fresh OAuth/2FA, multi-drive, external writeback, physical devices and other
unexecuted combinations retain their existing honest ledger status.

## Final regression and installed release

- The complete desktop UI suite passed16 tests/zero failures in333.176 seconds,
  including both new cancellation cases and all14 previous desktop cases.
  `/tmp/opencommander-b20-final-desktop-suite.log`; result
  `.build-native/ui-20261025/Logs/Test/Test-OpenCommander-2026.10.25_11-28-34-+0100.xcresult`.
- After moving the stored Task-state inspection into the main-thread callback,
  the exact final-source local three-mode cancellation and online byte-download
  cancellation tests were rebuilt and repeated:2 tests/zero failures in55.113s
  (34.239s and20.874s).
  `/tmp/opencommander-b20-native-final-tools.log`.
- Full writable NTFS Release1.3 Build20 was Developer-ID signed, notarized by
  Apple (`b5868092-02fd-458e-b6a6-bada8053859f`, Accepted), stapled and passed
  the full distribution/Gatekeeper gate. The test-only barrier strings are
  absent from the Release executable. An earlier signed/notarized candidate
  was not installed; only `developer-id-signed-20261025-b20-final` was installed.
- Queue observed empty; old app quit normally; no active NTFS mount before
  installation. Build19 backup retained at
  `ntfs/NTFS3G/.build-native/App-before-b20.sloHgO/OpenCommander.previous`.
  Exact installed Build20 distribution gate and normal launch passed. Original
  root/iCloud pane paths, language and configured locations were retained.
- Installed driver:22 PASS groups with own new64MiB image, actual FSKit write,
  independent Apple NTFS read-only reopen with exact bytes/timestamps and
  rename/delete persistence. Both mounts detached.
  `/tmp/opencommander-b20-installed-ntfs.log`. Not a physical Elements/NAS pass.
- All27 localization dictionaries and source whitespace checks passed.

## Actual Google Drive ↔ Dropbox acceptance on installed Build20

Both existing account connections opened without login. The only entered cloud
folders were their already-owned `OpenCommander-LiveQA-Size12-wUvOA0` QA trees,
left Google Drive/right Dropbox. The real comparison dialog identified both
complete paths. Start visibly warned that cloud files might need downloading.
Cancel during real provider processing produced the German cancellation text,
an enabled Start button and an independently observed empty result list (zero
`CommanderToolResult-*` elements). No equality was reported for that aborted run.

The subsequent Start completed with exactly two rows:

- `Gleich · Sub/b.txt`
- `Unterschiedlich · a.txt`

This matches the existing synthetic QA data (Drive a.txt is1234 newline;
Dropbox a.txt isABCD newline). No rename/upload/delete/share action was invoked.
The cancelled real run's precise network phase was not instrumented; the
five-second native synthetic case supplies the explicit inside-download proof.

The comparison closed normally. Right iCloud and left `/` were restored and
independently observed; original accounts/locations remain. TOOLS-04 is now
`native_verified` for this bounded original comparison/cancellation sequence,
not a claim about all provider/network/consent matrices. Ledger now53 native
verified,97 partial and8 environment-required; complete remainsfalse.
No new GitHub publication or OS reboot was performed.
