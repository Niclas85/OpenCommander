# Native queue controls and restart — 2026-10-19

Separate MacUITests app/profile; normal installed app untouched. Synthetic
QueueControls fixture: three distinct actual 64-MiB files Alpha/Beta/Gamma,
empty independent DestA/B/C directories. Original terminal-only queue backed up
unchanged; three paused fixtures appended with stable IDs and concurrency two.
No active queue was edited. Real controls/workers perform all subsequent I/O.

`queue-controls.swift` refuses existing fixtures; `queue-control-jobs.swift`
requires stopped test bundle, terminal-only old jobs, exact source sizes and
absent targets. DEBUG host injects 200-ms worker checkpoints only for this exact
bundle/root and QueueControls source AND destination paths when own flag exists.
Normal app has no delay, no control lock held while delayed, UI thread unaffected.
This is controlled slow local I/O, not a real network outage/latency measurement.

## Executed native control sequence

- Initial UI three Pausiert cards. Alle fortsetzen: Alpha/Beta running, Gamma
  queued at concurrency two. Single Pause Alpha: Alpha stops at 7,340,032 bytes,
  Beta continues and Gamma starts independently (14% and 1% observed).
- Alle pausieren: all paused, Alpha 7,340,032; Beta 44,040,192; Gamma 35,651,584.
  Persisted snapshot independently read twice remains identical; no visible
  final *.bin published while these jobs were paused.
- Repeated Alle fortsetzen clicks do not create duplicate jobs/stages; resume
  button disabled once no paused entries, two running/one queued observed.
  Alle pausieren again: Alpha 15,728,640; Beta 44,040,192; Gamma 35,651,584.
  Worker/state identity remains one per job.
- Found paused verification caption defect: Beta was paused with 44,040,192
  copied bytes but showed 33% from interrupted prefix checking. isChecking now
  applies only to running state; model regression protects 75%-copied vs
  25%-checked distinction, both active and paused.
- Found stale completed-retry error in card accessibility summary. Completed
  job no longer presents old attempt as current failure, while persisted prior
  failure evidence is retained and genuine failed-state messages still appear.

## Native restart and exact continuation

Regular app quit after persisted pauses; refreshed isolated clone to signed
`parity-20261019-queue-progress-final-build.log` (exit 0). On relaunch all remain
paused at exactly same byte counts. UI Alpha 23%, Beta 65%, Gamma 53%; previous
completed FullDiskSource card no stale free-space error. No automatic restart.

Explicit Alpha-only Resume visibly checks existing prefix, then completes one
64-MiB target. Beta/Gamma remain paused, unchanged. Independent cmp passes and
both source/target SHA-256:
dbfaca2662cb70b69dfefd5ac95d1f54a73663092d46cefdc9609dc695a12c98.
Native REC-02 and REC-04 bounded local sequences complete.

## Cancel subset and independent resume

Cancel paused Beta: only Beta becomes Abgebrochen — Teildaten behalten at 65%,
Gamma stays paused, Alpha completed. Beta source intact, no visible final target,
retained staging contains actual 44,040,192-byte partial payload. No cleanup
success claimed by app. Card removal means card-only, not deleting retained data.
Added retained staging path and explicit card-removal explanation to Details/
accessibility/copy-report; native validation of that addition passed below.

Explicit Gamma-only Resume completes independently after Beta cancellation;
cmp matches source and final 64-MiB target, SHA-256:
bba8d223a5d7360d992f29f04522ef380bef664d6d41c2e182dc02973dd3820b.
Active and queued cancellation, full overlap/move/delete reservation matrix and
every provider blocking-I/O boundary remain partial, not inferred from this.

## Regression/build evidence

- parity-20261019-queue-controls-regression.log: runner exit 0.
- parity-20261019-queue-progress-final.log: runner exit 0, new stale-error and
  paused-verification tests plus queue concurrency/aliases/paging/admission pass.
- Swift localization duplicate check: 27 dictionaries pass.
- parity-20261019-queue-retained-path-build.log: exit 74 at Swift package graph
  resolution, not a pass. Independent swift package dump-package exit 0 proves
  local NTFS manifest parses. Retry parity-20261019-queue-retained-path-retry-build.log
  exited 0 with valid signed host/extension security checks; no package/source
  reset or unrelated build interruption used to obtain it.

Final isolated native retest: Beta compact accessibility value and expanded
Details both show exact retained staging path and explicitly explain that card
removal does not delete the retained files. Copy-details control available;
user clipboard was not changed for this check. Existing 44,040,192-byte payload
and original Beta source preserved. Source/target Alpha and Gamma remain exact.

All three fixture jobs terminal before final app refresh: Alpha/Gamma completed,
Beta cancelled with explicit retained data. SlowQueueControls flag moved intact
to .saved, so no test slowdown remains active. No job was left running.

Only own fixtures changed, no personal deletion, no mount, no OS restart.

Final independent bounded Foundation read verifies retained Beta payload equals
the first 44,040,192 bytes of its original source exactly. Original Beta SHA-256:
07a1e6f3b84e57fbffcbc20ed126f43ceeaec19b8a1cdc0e63b3a75421e6dc54.
Process inspection confirms isolated app quit; normal installed app PID 13306
remains running and was not replaced.
