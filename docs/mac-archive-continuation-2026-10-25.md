# macOS special-case continuation — 25 October 2026

Scope: continue the existing Linux-parity ledger, excluding WebDAV. Personal
files/accounts are not reset or edited. No computer restart. Existing uncommitted
24-October work is preserved.

## Corrected product behavior

The native encrypted ZIP fixture exposed a real defect: ZIPFoundation's iterator
omitted the encrypted entry, presenting it as empty; extraction then threw Cocoa
260 (missing file). The unified log records `read-zip NSCocoaErrorDomain 260`.
The first diagnostic run was interrupted after its failed predicate stalled in
test failure handling; it is not a pass (`parity-20261025-native-archive.log`).

On Mac Catalyst, the full native archive header set is now validated before
ZIP listing, extraction, member materialization and archive properties. This
refuses encryption, unsupported special types, unsafe names and ambiguous
duplicates rather than silently offering a partial/empty archive. ZIPFoundation
still supplies supported ZIP data/CRC and stored timestamps. The operation is
asynchronous in existing listing/document/transfer workers; extraction preflight
honors cancellation, properties preflight retains its deadline.

Archive failures now have a localized, actionable explanation: damaged,
encrypted or unsupported entries are possible causes, and there is no supported
password assistant. Permission, missing physical source, cancellation and disk
space failures retain their distinct messages. Parser-internal English/path
details are not used as the user explanation. English/German formatter tests
verify this, including permissions/cancellation; all27 localization dictionaries
pass duplicate-key checks.

## Actual evidence so far

- `parity-20261025-encrypted-safety.log`: exit0,39 PASS groups. Includes existing
  archive path/link/size/preview/cancel/cleanup tests and a new actual ZipCrypto
  archive refused in both native preflight and extraction, with source bytes
  unchanged and no output directory. The public fixture was generated with system
  zip using `test-fixture-only` and independently passed `unzip -t` with that same
  public test password. Its payload is synthetic, not a credential or personal file.
- `parity-20261025-file-drop.log`: exit0,15 PASS groups.
- `parity-20261025-tools.log`: exit0,18 PASS groups, including deliberate child
  process kills for rename-journal recovery. Those expected `Killed: 9` lines
  are not unexplained app crashes.
- `parity-20261025-native-archive-corrected.log`: actual native empty/truncated/
  encrypted ZIP sequence passed15.799s. Empty state has no retry error; truncated
  input has an honest error; encrypted ZIP extraction reports unsupported
  passwords, creates no password fields or output, and preserves source bytes.
- The same run passed unsafe TAR listing AND extraction65.726s: traversal,
  absolute path pointing only to an owned sentinel, symbolic link, hard link,
  FIFO, device node, duplicate, case collision and declared size over4GiB.
  After every attempt, exact original archive/sentinel bytes were unchanged and
  the destination contained only its original empty DropHere directory.
- The normal ZIP positive test initially waited for a file without confirming
  the genuine macOS Save panel. The retained screen recording proves that panel
  was waiting normally. The next test queried Save successfully but stalled in
  XCTest's second hybrid AppKit/Catalyst button lookup; the run was interrupted,
  not passed (`parity-20261025-full-desktop-gate.log`). The corrected test uses
  Return on the observed default Save button. No Save-panel production change.

Fresh temporary UI products have their ad-hoc FSKit extension detached before
launch/signing so they cannot replace the installed `openntfs2` registration.
An initial fresh dependency resolver failed; the pinned existing ZIPFoundation
checkout exactly matches Package.resolved0.9.20/revision22787ffb59de99e5dc1fbfe80b19c97a904ad48d.
No dependency version was changed.

## Distribution candidate

Release Build17 was rebuilt with the complete approved NTFS2 identity and writable
condition, matching Build16. An earlier build without these explicit overrides
was correctly rejected by the signing script and was never installed. The full
candidate is `developer-id-signed-20261025-b17-full/OpenCommander.app` below the
ignored native build directory. Developer ID signature/profile/FSKit/helper gate
passes. Apple accepted notarization `1aa7d2ae-833b-469f-8917-dc0eb40d211a`; ticket
stapled, Gatekeeper/distribution gate passed. Private signing/notary credentials
remain outside app and repository. Installation is pending remaining relevant
native checks. Build16 remains installed until then.

This is not a claim of complete158-case Linux parity. Account/hardware-only
cases remain open; WebDAV stays excluded. No GitHub publication is performed by
this continuation.

## Final-source verification continuation

`parity-20261025-valid-zip-return.log`: actual normal ZIP creation, native Save
confirmation with Return, browse Pack/Note.txt, explicit extraction to the other
pane, exact extracted/source bytes, and unchanged archive passed15.669s. The
same positive test later passed16.218s in the shared run.

`parity-20261025-desktop-final-retest.log`: twelve native tests executed; eleven
passed. Normal ZIP, connections, copy/history/Undo, empty/truncated/encrypted ZIP,
history+paused queue, independent compact cards/restart, native pane drag,
search/path results, special-character inputs,20k entries and unsafe TAR
sequences are included. The sole failure was the pre-existing favourite test's
immediate absent-bar assertion after hiding, before the asynchronous refresh.
The failure handling made that case87.459s; this is not a claim that it passed.
The test now waits for rename-dialog dismissal and the actual hidden state,
as it already did for shortcut removal. Final-source targeted repeat
`parity-20261025-last-two-native.log` passed the full favourite sequence29.970s.

The final production refinement preserves the exact localized
`OpenCommander.ZIP/1` unsafe-path/size/count explanation instead of replacing it
with a generic unreadable-archive explanation. English/German permission,
cancellation and safety messages are tested. `parity-20261025-final-archive-safety.log`
exited0 with40 PASS groups: additionally admits exactly100000 distinct metadata
entries and refuses the100001st without creating/decompressing payloads.

Final Release Build17 was rebuilt after that formatter refinement; signed copy
is `developer-id-signed-20261025-b17-final/OpenCommander.app`. Apple accepted
`5e87db45-f320-43fe-97de-55c7886b7727`; ticket stapled and complete distribution
gate passed. This final candidate, not the earlier similarly numbered candidate,
is the one intended for installation.

Ledger now52 native_verified /98 partial /8 environment_required,158 total.
ARCH-05 states its exact bounded native TAR proof; ARCH-07 states empty,
truncated and actual ZipCrypto ZIP proof. ARCH-06 remains partial: native
over4GiB/special files plus entry-count/preview regression evidence do not
pretend to be a full100001-member GUI/128MiB-boundary matrix.

## Installed final result

`parity-20261025-last-two-native.log`: exit0,2/2 passed,97.482s total.
Favourite29.970s and final-source unsafe-archive sequence67.513s. Thus the twelve
distinct desktop sequences have successful evidence across the shared run and
targeted corrected repeats, not a fictional all-green shared run. The final
one-line ZIP-safety formatter refinement is independently covered by the40-group
safety run and this final native unsafe-archive repeat.

Normal installed queue preflight reported no saved jobs. Quit Build16 normally;
no active OpenCommander NTFS mounts. Preserved it at
`.build-native/App-before-b17.CeFqKn/OpenCommander.previous`. Installed the final
signed/stapled Build17 at `/Applications/OpenCommander.app`; CFBundleVersion17
and installed distribution gate passed. Native startup preserved German,
root/iCloud panes, Google Drive/Dropbox places and the existing SanDisk listing.

`parity-20261025-installed-b17-ntfs.log`: exit0,22 PASS groups. New isolated image
only, actual installed FSKit mount/read/write/copy/rename/replace/delete/truncate/
fsync and case/timestamp checks. Detach, independent Apple read-only NTFS reopen
with exact Unicode/517-byte content, rename/delete persistence and timestamps,
then successful detach. No Elements/SanDisk/NAS writes, remounts or formatting.

Final native Release GUI verification opened only the synthetic Protected.zip
in `/private/tmp/OpenCommander-EncryptedFixture.adRgcC`. The actual installed
app displayed the new German damaged/encrypted/unsupported/password-dialog
explanation with Cocoa259 and Retry, not an empty listing or false missing-file
message. Restored the previous left root `/`; right iCloud pane unchanged.
No personal files deleted; no account reauthorization/revocation; no OS restart.
No commit/push/release was performed in this install/test request.
