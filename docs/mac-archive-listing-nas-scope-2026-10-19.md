# Archive listing and scoped NAS access — 2026-10-19

## ZIP corrections and verification

`FileEntry.contentBytes()` no longer returns the synthetic zero listing size of
an implicit archive folder. It reads bounded archive member metadata for folder
or archive-root totals; failure is unknown, a genuinely empty archive is zero.
Duplicate member paths and summed integer overflow are refused. Non-ZIP native
listing now receives the same ten-second cancellation deadline for this path.

The ZIP date column now formats stored DOS wall-clock fields without an additional
viewer timezone conversion, consistent with the corrected properties sheet.
Non-ZIP/physical date display remains unchanged.

Full `tests/run-swift-safety.sh` exits0, **38 PASS groups**:
`parity-20261019-archive-listing-safety.log`. Added archive-root/empty-root and
Europe/Zurich + America/New_York stored-clock regressions. Final Catalyst build
and extension identity/signature/sandbox/FSKit gates pass, exit0:
`parity-20261019-archive-listing-build.log`.

Native clone refreshed from this exact candidate, extensions detached before
ad-hoc signing; preserved previous clone `Before-Archive-Listing.saved`.
Only own ArchivePropertiesAcceptance fixture used. Enter Properties.zip:
root summary8KB (not zero), folder summary8KB (not zero), nested folder/sub
summary **5 bytes** and only Five.txt. Actual screenshot shows Repeated.txt and
sub date columns **2026-10-19 13:26**, matching independent `unzip -lv`, not15:26.
The earlier properties report separately proves exact8197B folder sum.

## NAS permission-path isolation and actual resolution

The previous direct-path attempt hung only in the separate test app. No POSIX
filesystem bypass, full-disk-access toggle, TCC database mutation, network remount,
new network account or production-app change was introduced.

Instead used native test-app Settings / Locations → Add Location → Choose Folder.
Native NSOpenPanel Go To selected **only our existing synthetic folder**:
`/Volumes/Test/OpenCommander-LiveQA-20261018-qOIIyg/FoundationTree`.
This location contains own test fixtures, no personal data. Neither the whole
NAS share nor home/root was selected. Confirmed that exact folder; the test
profile gained one custom location/bookmark, not the normal app's preferences.

Native selection of the new FoundationTree location then immediately listed
Nested and summary6bytes. Status identifies Test · SMB(OS X) · read/write.
Command-I on Nested shows:

- exact own NAS path and URI, smbfs, volume read-only No;
- no implicit contents-size scan, then explicit calculate returns **6 B**;
- created/modified2026-10-18 18:44:47, accessed18:45:07;
- mode0700, ownerniklaus, groupstaff, current-process read/write Yes;
- actual reported volume capacity/free space;
- explicit caveat that provider-reported POSIX modes may be synthetic and
  observed access cannot guarantee a later operation.

Independent `stat` on that exact folder agrees with dates, mode, owner and group;
its directory inode size16384 is correctly NOT displayed as folder contents.

Closed the information sheet, quit test app normally and verified no test app
process remained (normal installed PID13306 stayed running). Relaunched the exact
same test bundle: it automatically restored FoundationTree, Nested and6-byte
summary, plus the custom location, **without a new folder selection or prompt**.
Quit test app normally afterward. The narrow persistent folder selection path is
therefore live-verified; the earlier all-files preflight denial is not reclassified
as a proven causal diagnosis.

## Scope still open

No new NAS writes were performed in this sequence; prior transfer evidence is
separate. Broader share permissions, denied/offline/remount and interrupted-write
matrix remain unproven for this candidate. Physical Elements is not available
in this sequence. New approvals were not used to broaden the scope of testing.
The overall158-case Linux-equivalence acceptance remains incomplete; WebDAV only
is excluded. Installed application is not replaced by these test clones.
