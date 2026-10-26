# Cloud navigation development after installed Build25

This is an explicitly incomplete development continuation, not an accepted
Build26 release. Installed Build25 remains unchanged and its29 native passes
and post-install22-group NTFS evidence are recorded separately in
`mac-transfer-metrics-parity-2026-10-26.md`.

## Implementation under acceptance

- A provider's foreground operation retains its mounted browser as navigation
  owner. The other pane may navigate local paths and open read-only provider
  lists. The owner cannot be replaced via Places or setRoot while active.
- Main mutation toolbar and History interactions remain unavailable; explicit
  mutation entry points also refuse while the foreground operation is active.
  Existing independent local workers may finish, but newly resumed/queued work
  stays behind the existing foreground scheduling gate.
- Other provider browsers may run listing-only reads, not another foreground
  mutation/preview. Their action menu is read-only and they do not offer recovery
  for potentially active journals during the operation. Global Cancel still
  refers to the original operation, not a later list request.
- A bounded DEBUG-only held download enables actual native navigation tests.
  It is inside the existing exact test-bundle/owned-root injected backend.

## Actual results, not full acceptance

Latest debug build succeeded:
`/tmp/opencommander-b26-ui-build-r4.log`.
An intermediate test compile failed because XCTest's query has no `lastMatch`;
corrected to an explicit matched index before the successful build.

Focused native run exited65: **three executed, two passed, one failed**:
`/tmp/opencommander-b26-navigation-native.log`, result
`ui-20261025/Logs/Test/Test-OpenCommander-2026.10.26_08-52-27-+0100.xcresult`.

- PASS actual synthetic cloud download/copy while the other pane navigates:
  destination stayed at original Right/DropHere/Proof.txt, not the newly opened
  Right/Proof.txt; bytes exact, source retained, History Undo removed the correct
  output.41.234s. Own fixtures only, not a live provider/network-loss test.
- FAIL held preview/navigation sequence at AppReviewVideoTests.swift:973:
  Command-L did not produce the expected read-only navigation dialog.269.401s.
  Steps after that assertion (second provider list, release, final restoration)
  are NOT passes. Cause remains to be diagnosed, not assumed to be a product or
  automation-only defect. No assertion weakened to manufacture a pass.
- PASS original cloud-preview cancellation/retry/no-mutation-history regression,
 22.264s.

Current cloud core suite independently exited0:
`/tmp/opencommander-b26-cloud-core.log`. Its actual SIGKILL children test durable
recovery; they are not crashes of the installed app. These core passes do not
replace the failed native keyboard case.

Remaining scope includes the failed shortcut, owner-pane navigation beyond the
currently pinned design, unrelated concurrent mutations and full provider/
external-app/device matrix. No full Linux parity, complete JOB-06 acceptance,
Build26 installation, signing/notarization or publication is claimed.
