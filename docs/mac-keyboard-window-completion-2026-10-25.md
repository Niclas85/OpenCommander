# Native keyboard and window continuation — 25 October 2026

Scope: continue software acceptance without WebDAV; preserve the existing dirty
worktree, personal files, accounts and installed Build23 until a verified update
is ready. No reboot. Existing guarded mouse-test authorization remains scoped to
our own fixtures. No new OAuth consent or public sharing in this continuation.

## Reproduced settings focus escape

Separate MacUITests app, own fixture
`/private/tmp/OpenCommander-MacUITest-KeyboardFlow.rqvCSu`.
Command-comma opened settings. Two Tabs and Down left a visible keyboard-focus
rectangle in the background right file pane, with no settings row selected.
This is a real keyboard ergonomics defect, not an inferred failure from an
accessibility click that did nothing. Screenshot and current CUA hierarchy
independently observed it.

Settings now consume Tab/Shift-Tab and Up/Down, select/scroll a row and draw a
visible blue border. Return edits/opens it; Space toggles a location's visibility
or appearance. Option-Up/Down reorder only locations, bounded at both ends;
Command-N opens the existing Add menu. Escape closes the panel only when no
dialog owns it. Rename has an explicit Save default action for Return. No file
operations were reimplemented.

The first language-keyboard implementation opened UIKit's native UIMenu with
performPrimaryAction; Escape left that menu displayed in both XCTest and an
independent CUA session, despite real menu-arrow navigation. Explicit menu-end
callbacks/dismissal did not fix the observed host behavior and were removed.
Mouse and keyboard now share one bounded, scrollable dropdown popover controller
with current-language checkmark, explicit arrow/Return/Space selection and
Escape/Cancel. The button remains in Settings and retains its downward arrow.
No private APIs, event interception or global accessibility settings changed.

## Queue keyboard path

Command-Shift-T opens/focuses Transfers. Tab/arrows select a card, Space/Return
toggle Details, P/R/C route through the existing enabled Pause/Resume/Cancel
buttons, and Delete removes only a forgettable card. Shift-P/R and
Command-Shift-Delete use existing atomic whole-queue controls/card removal.
Escape returns to the active file list. No auto-resume, new transfer engine,
source deletion shortcut or background file-pane command was introduced.
Opening the queue automatically during a copy does not steal the user's file
focus. Selecting a file explicitly leaves queue keyboard mode.

Both keyboard paths are documented in German/English help. Corrected a stale
help line that claimed Return renamed, while the actual desktop mapping is
Return=Open and F2=Rename.

## Focused native evidence

`/tmp/opencommander-b24-keyboard-native.log`: three tests, zero failures,
63.612s (individual rounded case durations22.993/21.963/18.657):

- Existing Cmd-C/Tab/Cmd-V exact copy, text-editing isolation, Cmd-F active path,
  Cmd-Y preview and Escape remain usable.
- Settings keyboard-only Tab navigation to own favourite, Space hide/show,
  Option-Up reorder, Return rename/Save, Command-N/Add-menu cancellation,
  Escape close and fresh-process persisted name/order. Own Keep.txt exact bytes
  unchanged. No personal location/profile was edited.
- Queue keyboard focus, F5 background suppression, Details, explicit resume of
  two own saved paused jobs, individual/all-completed card removal, exact
  source/output bytes and Escape close. Later additional pointer-return focus
  assertion is not retroactively included in this first pass.

Result:
`ntfs/NTFS3G/.build-native/ui-20261025/Logs/Test/Test-OpenCommander-2026.10.25_18-47-10-+0100.xcresult`.

Initial settings test used a text-field query tied to its old value after typing
the new name. That automation query became stale and hung diagnostic hierarchy
capture. Only the known own xcodebuild PID was interrupted; corrected test sends
Return to current focus and passed. This was not counted as a product pass or
an application crash. Existing mouse settings test also passed before that
failed keyboard query.

## Window-size test preparation

The legacy UIKit host does not reliably expose a windowScene for native sizing.
Native AppKit now also enforces the intended900×600 minimum on the actual main
window. A DEBUG-only, exact MacUITests bundle/validated owned-root gated hook
requests actual900×600 and1366×768 window frames; no display/system preferences
are changed. Release has no geometry-test arguments/hook.

An initial scene-only size request did not resize the window; no compact-window
pass was claimed. Later native hook initially rejected the fixture because
Foundation canonicalizes `/private/tmp/...` to `/tmp/...`, unlike realpath.
The bounded guard now matches Foundation's observed canonical form. The
intermediate size waits were stopped by interrupting only their exact known
xcodebuild processes; original large-window screenshots remain non-passes.

The actual900×600 window was then independently observed in CUA (1800×1200
Retina screenshot), with readable settings and scrollable file columns. Native
assertions passed toolbar-button containment/hit checks, both path fields and
own Alpha.txt; dropdown frame was inside the real window. A direct XCTest
isHittable query on the old menu button stalled; it was replaced by real picker
interaction rather than treating an unexecuted click as a pass.

After switching to the shared popover, native test observed
SettingsLanguageChoices and LanguageChoice-de; Escape actually removed the
picker while the settings button remained. The next pointer reopen was blocked
by a separate macOS `Hinweis` dialog from UserNotificationCenter. CUA refused
that protected app; no alternative UI backend, credential entry, security change
or automatic confirmation was attempted. An asynchronous request asks the user
to read/close it without granting new permissions. Only the known own xcodebuild
PID76543 was interrupted. The new full two-size/pointer-language/queue test is
NOT marked passed;1366-width and final-source queue pointer-return checks still
need completion. `/tmp/opencommander-b24-picker-native.log`.

Fresh transfer-queue core and handbook suites passed; logs
`/tmp/opencommander-b24-queue-core.log` and
`/tmp/opencommander-b24-handbook.log`. Localization duplicate-key and whitespace
checks pass. Complete original Linux/provider/display prerequisites are not
automatically promoted by these focused passes.

## Prepared release candidate; installed version deliberately unchanged

- Exact current product source built full writable NTFS Release1.3 Build24:
  `/tmp/opencommander-b24-release-build.log`, BUILD SUCCEEDED.
- Fresh passes:33 queue,41 file safety,15 drop,19 tools,87 cloud and2 handbook
  groups; all script exits0. Logs `/tmp/opencommander-b24-{queue-core,file-safety,
  drop-core,tools-core,cloud-core,handbook}.log`. Expected SIGKILL children test
  durable recovery; they are not unreported application crashes.
- Real disposable FTP/FTPS/SFTP key/password loopback:8 PASS groups, exit0,
  including TCP loss/retry, isolated encrypted-key agent, real ten-second expiry
  refusal and explicit unlock/reconnect. `/tmp/opencommander-b24-remote-live.log`.
- All27 localization dictionaries pass duplicate checks; whitespace and JSON
  ledger parsing pass. Eight synthetic NTFS distribution-profile policy tests
  pass. Release bridge excludes both window-test arguments/state.
- Signed full candidate:
  `ntfs/NTFS3G/.build-native/developer-id-signed-20261025-b24/OpenCommander.app`.
  Apple Accepted submission `119dbdc9-6b4a-4fd9-8915-2b12f4f64f85`; stapled and
  complete distribution gate PASS (Developer ID, distribution profiles, helper,
  writable FSKit, notarization, Gatekeeper).
  `/tmp/opencommander-b24-sign.log`, `...b24-staple.log`, `...b24-distribution.log`.
  Existing publisher keychain profile only; no secret read/output or bundled key.
- No installation, new Git commit/push/release, account authorization, new
  security permission, physical-device mutation or OS restart. Exact installed
  `/Applications/OpenCommander.app` still independently reports Build23.
  Candidate24 is not promoted as fully GUI-tested or installed while the
  protected system dialog prevents the remaining real UI checks. User response
  to the scoped read/close request is still required; no alternate computer
  backend is used to work around CUA's protected-app refusal.

The current installed driver was independently rechecked while GUI testing is
blocked. Discovery again omitted the pluginkit-registered installed module
(advisory, not evidence of disabled activation). Actual normal-user FSKit mount
then passed all22 image-test groups, including real Unicode write/read/rename/
replacement/delete/truncate/fsync and independent Apple NTFS readonly reopen.
Both `/dev/disk6` mounts detached. Only newly created64MiB image
`.build-native/fskit-fixture.Rl6xzu/test.ntfs` was used; no physical disk/NAS test
is inferred. `/tmp/opencommander-b24-installed23-ntfs.log`, exit0. This checks
installed Build23, not an unperformed Build24 installation.
