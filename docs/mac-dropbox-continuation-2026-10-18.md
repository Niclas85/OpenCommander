# Dropbox and remaining Mac parity work — 2026-10-18

Work in progress, following commit `5b5c70c`. Latest fetched Linux reference is
still `e3b2981` on `origin/codex/linux-desktop`. Complete parity is not claimed.
The tested correction was installed at the end of this continuation; complete
Linux parity remains unclaimed.

## Implemented and verified

- Online properties now offers an explicit, cancellable folder-size scan with
  partial results for unknown sizes, inaccessible directories, traversal/time
  limits and overflow. Recovery directories with valid UUID names are excluded.
  No file payload is downloaded for this scan.
- Google Drive live fixture: `OpenCommander-LiveQA-Size12-wUvOA0`, containing
  `a.txt` (5 bytes) and `Sub/b.txt` (7 bytes). UI upload and readback completed;
  properties initially displayed no recursive size; clicking Calculate displayed
  exactly 12 bytes with progress/cancel controls.
- Dropbox connected successfully as profile
  `6888EFA3-861B-4A19-8AFA-C89C157D2CFB`. Its login survived regular app quit and
  a fresh candidate process. No account token is recorded here.
- The same fresh folder uploaded to Dropbox. Independent rclone listing and
  readback through a private configuration copy matched both files exactly.
  Dropbox properties also displayed 12 bytes. Conflict Cancel preserved the
  provider's original bytes, independently downloaded and compared again.
- A pending OAuth child from an earlier app process was found orphaned on
  loopback port 53682, parent PID 1. Its exact command was matched to our own
  failed setup UUID before SIGTERM. RcloneProcessRunner now has permanent
  shutdown/cancellation, invoked through AppDelegate and AppKit termination.
  A real isolated listener test verifies termination, port reuse and refusal of
  new subprocesses after shutdown. This does not claim SIGKILL parent cleanup.

## Automated/build evidence

Under `ntfs/NTFS3G/.build-native/`:

- `dropbox-client-resumed.log`: exit 0, 58 PASS groups, including folder-size
  cases and 22 fresh-process recovery phases.
- `dropbox-shutdown-check.log`: exit 0, nine runtime groups including listener.
- `dropbox-oauth-check.log`: eight schema/PKCE/loopback/exchange/packaging groups.
- `parity-tools-check.log`, `parity-drop-check.log`, `parity-handbook-check.log`:
  runners completed successfully.
- `dropbox-shutdown-build.log`: signed Catalyst build and V2 extension checks
  succeeded. `dropbox-diagnostic-build.log`: temporary diagnostic build succeeded.
- Initial folder-size fixture accidentally used a non-UUID recovery suffix;
  that expected-count assertion failed correctly. The corrected fixture passed.

## Open live failure: Dropbox folder replacement

Replacing the fixture with local `a.txt = ABCD\n` failed with sanitized
`cloud_request_failed`. The original provider folder and a recovery copy remain;
replacement job `061826BA-BC03-4C27-8AB5-D9E13E9AB253` was preserved in private
CloudReplacements storage. An explicit UI Resume failed as well.

An independent CLI rename succeeded; the earlier combined scratch copy/move
command did not stop after failure, so its exit status is not evidence of a
successful protective copy. To isolate the pending
rename, the original own fixture was moved using the exact CLI flags to the
already planned `.OpenCommander-Replaced-061826BA-BC03-4C27-8AB5-D9E13E9AB253`.
This is a diagnostic action, **not** a successful app replacement test. Resume in
the fresh diagnostic build is currently verifying/uploading its durable payload.
A fresh replacement must still pass fully inside the app before acceptance.

The temporary, private DEBUG diagnostic identified the actual failure:
`operation=copy`, exit 1, `from_write/too_many_write_operations/` for `a.txt`.
The failure was inside the protective copy, before the original folder rename.
The earlier rename suspicion was not the cause. The diagnostic block has now
been removed from source; do not install the earlier diagnostic product.

Dropbox command plans now force one transfer/checker and synchronous batch
completion. Namespace write contention and `too_many_requests` are classified
as sanitized rate limits with a cooldown. Mutation retries remain disabled.
See [Dropbox performance guidance](https://docs.dropboxapi.com/dropbox-api/docs/performance)
and [rclone Dropbox batching](https://rclone.org/dropbox/).

The first failed job was reconciled after the diagnostic CLI rename and is not
a fresh app-only replacement pass. A second app-only replacement reproduced the
copy failure, preserving job `F101DC0B-8400-481E-93BB-0CCCEA94DBF0`. Corrected
build/recovery initially remained pending. Serialization alone did not resolve
the provider contention. Dropbox protective copies now disable the server-side
Copy optimization (`--disable Copy`), using streamed read/upload instead.
The isolated streaming-copy test completed with matching provider hashes.
The corrected signed candidate resumed job F101 entirely in the app, finished
successfully and its downloaded `a.txt` matched the local `EFGH\n` payload.
App Undo completed with the explicit UI result `1 Aktion(en) rückgängig gemacht`.
An independent download matched the previous ABCD payload byte-for-byte.
A fresh app-only replacement (including a new empty subfolder) also completed.
Independent recursive download, with empty directories preserved, matched the
entire local source with `diff -r` (exit 0). The second Undo was refused by
Dropbox namespace rate limiting. The UI reported the sanitized error rather
than success and retained Undo. After waiting beyond the reported cooldown,
an explicit second attempt was started. It completed with the UI result
`1 Aktion(en) rückgängig gemacht`. Independent download confirmed the prior
ABCD bytes, unchanged `Sub/b.txt`, and removal of the newly introduced empty
directory from the visible restored version. The first rate-limited attempt
is not counted as a pass; the explicit recovery attempt is.
The file-drop runner was rerun: all 15 groups, including 32 modifier policy
combinations, passed. This is not an external live mouse acceptance.
The guarded external mouse driver refused the current gesture because Codex
and Safari covered the endpoints; no mouse events were sent. A request to
uncover the two fixture windows was sent without blocking software checks.
After the user replied `funktioniert`, the own Finder export fixture was opened
again and raised through accessibility. Two guarded window-position attempts
still refused to send events: Codex covered the source; Safari, then iPhone
Simulator, covered the destination. This is an automation/environment blocker,
not evidence of a Dropbox file-drop defect or a successful native drop.
After the user uncovered the windows, the guarded real mouse drag from the
Dropbox fixture row to the Finder fixture succeeded. Finder visibly displayed
the exported folder, and `diff -r` against the independently downloaded restored
version exited 0. A subsequent real pane-to-pane drag of the local `ImageQA`
folder started Dropbox upload with visible cancellable progress.
That real drag upload completed; independently downloaded PNG bytes matched
the original. Opening ImageQA showed loading progress and the uploaded image;
the toolbar Preview opened the built-in image viewer with the expected blue
fixture, correct Unicode title and page 1/1. Space-key behavior is not signed
off by this sequence. A real Command-drag of the exported Finder fixture into
the empty local Received pane completed as Move: source absent, full target
matches. Toolbar Undo restored the Finder source exactly and removed the
visible Received target. One initial guarded attempt was covered by Codex;
raising the permitted app window resolved it without controlling Codex.

## Installation

The candidate was quit normally after tests, with no NTFS mounts present.
The existing signed normal-host/V2-extension installer passed signature and
entitlement preflight, then moved the tested bundle to
`/Applications/OpenCommander.app`. Previous version is retained at
`ntfs/NTFS3G/.build-native/App-before-install.0eT7uP/OpenCommander.saved`.
Installed debug dylib SHA-256 matches the tested candidate:
`91dd74473e4e94ccab40a47697479dca2a61e45c7b500cffb23904a0f15ac05f`.
The installed path was launched and Dropbox reopened without a new sign-in.
No reboot, disk mount, new security approval, commit or push was performed.
The cloud-runtime runner was rerun after this change: all ten groups passed.

Private CLI config and original-byte readbacks are in
`/private/tmp/OpenCommander-DropboxProbe-AVbY0o` (0700 directory; config 0600).
They must not enter Git. The actual app-owned configuration was not modified by
the independent probes. Extra scratch folders in Dropbox start with
`.OpenCommander-LiveQA-Rename[d]-AVbY0o`; all are own disposable fixtures.

At the end of this Dropbox correction, the observed implementation gap was:
conflict Replace disabled for
online moves (`allowReplacement: !move`). Download-move publication also refuses
local replacement backups. Do not enable this without durable recovery/Undo
coverage. Full live Dropbox move/Undo, preview, external drag-and-drop and the
remaining manual Linux inventory are still open.

Subsequent implementation and evidence for move replacement are tracked in
`mac-cloud-move-replacement-2026-10-18.md`; this section records the earlier
installed correction, not the current source's final acceptance status.
