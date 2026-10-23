# Archive properties parity — 2026-10-19

## Implemented

Fresh archive member properties now use the archive directory rather than cached
listing size/date or physical container metadata. ZIP members display exact
uncompressed/compressed sizes and stored DOS timestamp. Implicit archive folders
display content bytes and entry count, with a slash-boundary prefix (not similarly
named siblings). Reads are bounded to 100,000 ZIP headers and ten seconds; no
extraction or cloud hydration is performed. Non-ZIP formats use the existing
bounded native archive listing and report unavailable compressed metadata unknown.
Missing/duplicate selected files and size overflow do not fabricate values.

ZIPFoundation's local checked-out `Date+ZIP.swift` uses `timegm()` to decode DOS
wall-clock fields and `FileManager+ZIP.swift` exposes that value as modificationDate.
Applying the user's timezone again shifted the fixture from 13:26 to 15:26.
The properties formatter now preserves those raw clock fields and explicitly
explains that ZIP timestamps carry no timezone. No third-party dependency changed.

## Regressions and builds

- `parity-20261019-archive-properties-safety.log`: full runner passes initial model.
- `parity-20261019-archive-properties-final-safety.log`: exit0, 37 PASS groups,
  including fresh properties, archive member/compression/date, implicit folder
  size/count/prefix boundary, stale missing/duplicate refusal, overflow, and German
  timezone-neutral ZIP timestamp under Europe/Zurich.
- `parity-20261019-archive-properties-build.log` and final-build.log: exit0,
  Catalyst BUILD SUCCEEDED and exact extension signature/identity/sandbox/FSKit
  gate pass. The final signed candidate includes the timestamp correction.

## Actual native observations

Only separate `com.github.niklaus85.OpenCommander.MacUITests` clone, with extensions
detached before signing. Installed normal app PID13306 unchanged. Synthetic fixture:
`/private/tmp/OpenCommander-MacUITest-Special-20261019-dYWldw/ArchivePropertiesAcceptance`.
Generator `ios/tests/MacAcceptanceTests/archive-properties-fixture.swift` refuses
a running test app or preexisting fixture. `zip -D` deliberately creates implicit
directories. Independent `unzip -lv` reports:

- `folder/Repeated.txt`:8192B, deflated25B, 2026-10-19 13:26:22.
- `folder/sub/Five.txt`:5B, stored5B.
- `folderish/Outside.txt`:13B, excluded from folder selection.

Native Enter opens archive in same pane; Command-I on `folder` shows own archive
path, content8197B, entries2, unknown directory timestamp rather than container
date, and no recursive physical-folder scan action.
Native Command-I on `Repeated.txt` shows own member path, size8192B and compressed
25B. Initial visible15:26:22 exposed the timezone bug. After final build and clone
replacement, native repeat shows **13:26:22**, matching the stored ZIP clock,
with German no-timezone caveat.

While the old member remains selected/listed, own Properties.zip was temporarily
renamed to exclusive `Properties-WhileMissing.saved`. Command-I correctly shows
unknown size/date and a German changed-archive/reload explanation, not stale8192B.
The exact same archive was restored; `unzip -t` passes all three members and native
physical listing again shows Properties.zip. Nothing was extracted/deleted.
Test app quit normally at end; normal installed app stays running.

## NAS diagnosis, not a pass

TCP445 on192.168.0.22 responds. Own existing
`/Volumes/Test/OpenCommander-LiveQA-20261018-qOIIyg/FoundationTree` lists Nested via
standalone Foundation in0.043s and POSIX in0.003s. Native test-app access still
waits in `NSFileManager.contentsOfDirectoryAtURL` → `DirEnumRead` → `open`, as
confirmed by one-second sample of exact test process91615 (not normal app).
Trace retained at isolated root `ArchiveProperties-NAS-sample.txt`.
The same live app was reobserved and displayed loading/retry; local navigation
remained functional. No unsupported POSIX bypass was introduced.

Read-only TCC log inspection found an AllFiles **preflight denial** for that test
identity, but this alone does not prove that it caused the network open wait;
no definitive NetworkVolumes authorization failure or usable prompt was observed.
No new disk-access/network permissions granted, no TCC database edits, no remount,
no normal-app restart, no OS restart. Live NAS properties remain open.

## Remaining known archive display issues

Properties now preserve ZIP wall-clock time, but ordinary listing's cached ZIP
dates still use the older UTC interpretation and need separate alignment.
The implicit ZIP directory's pane summary can still report zero from its cached
synthetic folder size; it must use actual bounded contents or unknown instead.
Non-ZIP native property UI, duplicate-header corrupt ZIP UI, ZIP64/large archive
limits, complete keyboard/scaling/provider matrices remain separate unproven cases.
Master ledger remains47 native_verified /102 partial /9 environment_required,
158 original cases and incomplete; WebDAV alone stays excluded.
