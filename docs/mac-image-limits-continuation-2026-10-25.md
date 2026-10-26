# Image resource limits continuation — Build21, 25 October 2026

Scope: continue the Linux/cloud special-case ledger without WebDAV. Preserve
existing changes, accounts and personal data; no OS restart or publication.

## Correction

The coordinated raster-image loader previously read an unrestricted source and
accepted any requested output size. It now opens the prepared source with
nonblocking/close-on-exec flags, checks the actual descriptor is a regular file,
rejects input over128MiB before reading and rechecks the accumulated byte count
while reading. Only one extra byte can be read to detect growth past the limit.
Missing/access/provider errors remain distinct from decoding failures. The
viewer distinguishes a size refusal, an unsupported special file and a corrupt
image, with English/German messages. Other languages retain the normal English
fallback for the new keys. No original is modified by preview or retry.

Requested decoded raster output is clamped to4096 pixels per dimension (at most
16,777,216 output pixels). This is an output-dimension bound, NOT a claim that
ImageIO's total decoder allocation is limited to64MiB. Source buffers, decoder
working memory and UIImage storage are additional allocations.

This applies after archive extraction/cloud materialization, in the shared
raster viewer. It does NOT yet bound a preceding provider download/extraction,
QuickLook SVG, native thumbnail inputs, videos or every provider's stall timeout.
MEDIA-09 therefore remains partial, not a complete Linux/all-provider pass.

## Initial verification

- Standalone image suite:11 PASS groups. Added empty/exact/over-limit bounded
  reads, a sparse128MiB+1 refusal without allocating that input, FIFO/directory
  refusal, unchanged sources, excessive/negative output-size requests.
  Existing coordinated JPEG/PNG, corrupt/missing/preparation errors, prepared
  archive URL, text boundaries, temporary ownership and replay policy pass.
  `/tmp/opencommander-b21-images.log`.
- All27 localization dictionaries pass duplicate-key validation.
- First UI attempt could not enable macOS automation mode and never entered
  a test body; this is not a passing test or an application failure.
  `/tmp/opencommander-b21-native-image.log`.

## Final evidence and honest limitations

- Cloud client suite:86 PASS groups, including independent-process recovery
  after interrupted transfers/replacements/moves and actual SIGKILL of isolated
  synthetic backend children. OneDrive suite:24 PASS groups. Swift file safety:
  40 PASS groups. Logs `/tmp/opencommander-b21-cloud-client.log`,
  `/tmp/opencommander-b21-onedrive.log`, `/tmp/opencommander-b21-file-safety.log`.
  These are not fresh live mutations on every personal cloud account.
- UI test build succeeded, including the new
  `testImagePreviewRejectsOversizeAndCorruptionAndRecovers` regression. All three
  execution attempts failed to enable macOS automation mode before any test
  body. The attempted full desktop suite did not execute; no new17-test pass
  is asserted. Logs `/tmp/opencommander-b21-native-image.log`,
  `/tmp/opencommander-b21-desktop-suite.log`,
  `/tmp/opencommander-b21-native-image-retry.log`.
- Used the separate DEBUG clone with its exact test ID and validated private
  fixture root `/private/tmp/OpenCommander-MacUITest-B21-tH4uWy` through visible
  computer control instead. Its selected sparse Limit.png displayed the actual
 128MiB refusal. Replacing ONLY that own test fixture with corrupt bytes and
  selecting Try Again changed the message to the actual image-decoding error.
  Replacing it with our known PNG and retrying removed the error/retry controls
  and visibly displayed the blue/yellow test image. Source equality was checked
  independently after both corrupt and valid preview. Escape returned normally.
  This is a bounded visible acceptance, not a full desktop suite pass.
- Full writable NTFS Release1.3 Build21 was Developer-ID signed, notarized
  (`548df5df-2bf5-4589-8dff-adcc9552ec5c`, Accepted) and stapled. Distribution
  gate passed for the signed candidate and exact installed app: authorized
  profiles, writable NTFS2 extension, helper, Gatekeeper and notarization ticket.
- Observed empty transfer queue, quit old app normally, verified no active
  openntfs mount, and installed the signed candidate in `/Applications`.
  Build20 remains recoverable at
  `ntfs/NTFS3G/.build-native/App-before-b21.7ck8L8/OpenCommander.previous`.
  Installed version independently reads21; normal launch preserved German,
  configured online locations and original root/iCloud pane paths.
- Installed Build21 preview of the own sparse fixture via Space displayed the
  actual German128MiB refusal. Pointer attempts on the production toolbar did
  not establish an opening and are not counted as a toolbar acceptance; the
  separate clone's visible preview/retry sequence above did succeed. No cause
  for those production pointer attempts is asserted without further evidence.
  Left `/` and right original iCloud path were explicitly restored and observed.
- Installed FSKit:22 PASS groups using only a NEW64MiB image, including actual
  write/read/rename/replace/delete/truncate/fsync, exact Unicode and timestamps,
  then independent Apple NTFS read-only reopen. Both mounts detached. This does
  not claim a fresh physical Elements or NAS pass.
  `/tmp/opencommander-b21-installed-ntfs.log`.

Full Linux/cloud parity remains incomplete; ledger statuses are unchanged at
53 native_verified,97 partial,8 environment_required. WebDAV remains excluded.
No personal files were deleted, no publisher secrets were bundled, no OS
restart or GitHub release was performed in this continuation.
