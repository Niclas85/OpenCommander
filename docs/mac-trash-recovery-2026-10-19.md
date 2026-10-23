# Trash recovery and Finder Put Back investigation — 2026-10-19

Only own synthetic objects. Normal installed app PID 13306 untouched, no OS reboot,
mount, added access grant, personal deletion or Trash emptying. Goal remains active.

## Verified Finder behavior (not assumptions)

trash-bookmark-probe.swift creates unique own directories and a pre-mutation
manifest with identity/content expectations and bookmark, deliberately no final
Trash path. Post-call destination observations are separate from recovery input.

- Actual Finder UI selects only own FoundationStaged probe; File → Zurücklegen
  disabled. Own NSWorkspaceOriginal comparison: also disabled. Thus replacing
  Foundation with NSWorkspace.recycle alone does NOT pass this acceptance here.
- Positive control created under same /private/tmp test tree, selected exclusively
  and moved by Finder Cmd-Backspace: its Zurücklegen is enabled, actual native click
  restores exact own original location. This rules out a blanket /tmp restriction
  or permanently disabled menu as explanation. No private Finder metadata was
  edited and no Finder automation permission was requested.
- APIs tested through a native AppKit CLI probe, not a claim about every app/OS.
  Finder Put Back integration remains open; OpenCommander verified Undo remains
  supported. Do not claim the item would merely return to staging: tested menu
  is disabled, so no such movement occurred.

## Bookmark feasibility / failed alternatives

Independent process resolver reads only pre-mutation plan/bookmark, not observed
destination and not a Trash listing. Minimal bookmarks recover exact original
identities/content after Foundation direct, Foundation staged and NSWorkspace
moves. But direct original-path reuse resolves to NEW object: identity guard
correctly refuses. Full/default and suitable-for-bookmark-file alternatives also
resolve to replacement, so these are recorded failures, not fallback solutions.

The actual queue uses a PRIVATE unique staging location, not user-visible path.
StagedOriginalPathReused probe succeeds: new object at user original path stays
untouched, pre-mutation staging bookmark resolves exact old object now in Trash.
Feasibility logs under .build-native/parity-20261019-trash-*-bookmark-*.log.
All seven API probes restored by matching exact created inode and original text;
synthetic replacement versions retained separately. Finder positive control
restored by native Finder. No other Trash entry was modified.

## Implementation

Before OS Trash action, queue fsyncs private selected-bookmark.json with job UUID,
full selected identity, opaque bookmark and independent 32-byte full content/
metadata/tree proof. File is exclusive/no-follow mode 0600 in owned mode-0700
staging; metadata publication and directory are synced. Bookmark explicitly omits
implicit security scope; resolving has no UI, no mounting and no implicit access
start. It does not replace ordinary filesystem permissions or grant access.

On explicit resume with payload missing and receipt absent, validate bookmark,
UUID, expected identity, full proof AND actual Trash containment before adopting
the recovered destination. Never delete or overwrite a new original-path entry.
An exact original restored by cooperative pause is allowed only at its original
path; arbitrary other bookmark locations are refused. Recovered completion writes
receipt normally, then queue completion/history pipeline. No global Trash scan.
Cooperative cancellation before OS mutation restores still-selected staged item
without overwriting a new occupant. A possible already-completed OS action is
never misrepresented as a successful no-effect cancellation.

DeletionCheckpoint dependency injection is nil in the product controller;
only standalone test children use it to die at exact mutation/receipt boundaries.
No runtime kill flag or production self-termination feature was introduced.

## Six ACTUAL SIGKILL tests

tests/run-deletion-crash-tests.sh exits 0 after hardening:
parity-20261019-deletion-crash-final.log. Fixture
/private/tmp/OpenCommander-DeletionCrash-3919AD9E-8547-4111-B259-7C3370FB2DE7.
File, nested Unicode folder/empty dir/external link, and selected symbolic link,
each killed after actual OS Trash return BEFORE receipt and AFTER receipt before
final queue publication. Parent verifies uncaught SIGKILL termination status 9,
actual intended receipt absence/presence and pre-mutation bookmark persisted.

Parent then creates unrelated new directory/file at old source path. A NEW process
opens saved queue paused (no automatic mutation), explicitly resumes, completes
with exact old destination identity and full proof, preserving new source snapshot.
Own original is then restored exactly, new version separately retained, external
symlink target unchanged. No recovery input contains the missing destination.
These are real Core/OS Trash process deaths, not just a rewritten state JSON.
No Mac reboot, USB disconnect, physical NTFS/NAS or whole Catalyst GUI kill is
inferred from this runner. Entire existing queue regression also exits 0:
parity-20261019-deletion-bookmark-hardened-regression.log.

Earlier first compile was invalidated by editing an input while Swift compiled;
not executed/not a pass. Earlier successful run printed misleading "SIGKILL
unexpectedly returned" just before mandatory signal delivery (actual status was
9); harness now waits for delivery without false fatal diagnostics. Final clean
run above passes all six without those messages.

## Catalyst native smoke / separate fresh process

Signed candidate parity-20261019-deletion-bookmark-build.log exits 0 with security
checks. Isolated clone extension detached; normal app not replaced.
Own MacBookmarkSmoke.txt, paused blocker ..C801, native Delete → Trash creates
job 8155A3F4-5384-4616-88DC-3A82210A30B7 with explicit waiting reason. Cancel blocker
releases it; completed after ~2.54 s. Actual pre-OS bookmark and receipt persisted,
destination /Users/niklaus/.Trash/MacBookmarkSmoke.txt, exact 59-byte original.
SHA256 65334e93f6cb3840bdede3d441c4bfcb14aa28cc22e72a9fe38eb5b6440ca1a3.

Regular quit, confirmed process gone, fresh native app launch, then Undo: original
reappears, German success, real Trash entry gone. No new permission prompt and no
security scope embedded. This verifies Catalyst API support and fresh-process
ordinary Undo, NOT Catalyst GUI kill at the missing-receipt point (still separate).
Regular quit; all isolated fixture jobs terminal, sources/recovery evidence kept.

Independent stopped-app verify-trash-bookmark-smoke.swift exits 0: restored exact
UTF-8 original, UUID-matching reference with opaque bookmark and 32-byte proof,
matching receipt, old Trash destination absent after Undo, no copy output, blocker
cancelled, all IDs unique and terminal. No other app was terminated.

## Remaining

Finder Put Back integration, actual Catalyst GUI kill/import acceptance,
volume remount/reboot, unavailable filesystems, parent rebinding and full external
race/hard-link matrix remain unproven. No full Linux or release-ready claim.
