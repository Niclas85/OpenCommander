# Keyboard/dialog continuation — 2026-10-23

## Scope and verified reference

Fresh23-Oct fetch of `origin/codex/linux-desktop` succeeded; reference remains
`e3b2981ad5a88551be81b86b6c6453e26e2e2ff5`. WebDAV remains excluded.
This advances PROP-04/05/07, not a claim that all158 cases are complete.

The19-Oct test root was absent after the interruption, not treated as a live
process or reconstructed evidence. Saved source/build/test logs remain. No
OpenCommander process was running at23-Oct entry. Production app was not replaced,
launched or changed during the following checks.

## Implemented corrections and19-Oct evidence

Reproduced native Command-F → Escape: original tool sheet stayed open.
`CommanderToolsController` now routes Escape through the existing Close action.
While busy this requests cancellation and waits for I/O/rollback, rather than
dismissing an active operation. Idle Escape closes. This applies to search,
compare and multi-rename. No duplicate cancellation implementation added.

Read-only scrollable information now has its own Escape responder. Separately,
settings and help embedded controllers gain Escape close handling. Parent file
key commands are disabled while settings/help are open, preventing background
F5/Delete/Undo from acting on a previously selected file. Native language-menu
Escape is left to the system first, before a subsequent Escape closes settings.

19-Oct native tests on the earlier isolated profile established:

- Command-F/Option-Command-C/Shift-Command-M open correct tool modes; idle Escape
  closes all three, including focused editable query field.
- Immediate Return-to-start + Escape in a single input sequence on own100,100-file
  ToolsLarge fixture produced explicit German cancelled status, zero results and
  restored controls while sheet remained open. Second Escape closed. Earlier
  spaced attempts allowed fast search to finish before Escape; those do NOT
  establish busy cancellation.
- Command-I information opened and Escape closed.
- Selected Properties.txt plus active filter: Command-A/X/V edited filter text;
  F5 and Space did not trigger file actions; Command-A/Backspace cleared filter.
  Source SHA remained5014690b87ccb4f50fe059d97dcfd9545c425808fc98eb3eb8d9ba49795eed05,
  and queue count remained36. Settings Escape was still missing in that intermediate
  build and was then corrected, not called passed retrospectively.

Build logs `parity-20261019-dialog-escape-build.log` and
`parity-20261019-panel-keyboard-build.log` each end BUILD SUCCEEDED and pass exact
extension identity/signature/sandbox/FSKit checks. The latter includes settings,
help and background-command protection.23-Oct clone uses this exact saved build;
source timestamps precede its successful build and no product code changed23-Oct.

## Fresh23-Oct native final-build checks

New own fixture `/private/tmp/OpenCommander-MacUITest-Keyboard-20261023-Ip3UqS`.
Left/Keyboard.txt45B; Right/Sentinel.txt36B. Separate MacUITests app clone only,
extensions detached before signing; PreserveAppState marker ensures subsequent
launches preserve preference changes. Initial English/light test profile observed.
Old isolated custom-location references were not visited or broadened.

- Select Keyboard.txt → Command-comma opens settings. F5 then Escape closes panel
  without creating a transfer or changing either directory.
- F1 opens help (HelpSearch/HelpClose observed). F5 then Escape closes it without
  background file action. This checks controls/shortcut routing, not loading every
  handbook chapter in that brief sequence.
- In settings choose dark toggle and Deutsch from native dropdown. Escape from
  menu closes menu only, leaving settings; subsequent Escape closes settings.
  Parent labels then change to German and dark appearance. Screenshot visually
  checked readable controls/selected row in this observed window, not every scale.
- Regular quit, independently verify process absent, fresh exact clone launch:
  German labels and dark theme persist. This proves DE/dark persistence, not a
  fresh all-provider/all-resolution appearance matrix.
- Command-I on45B Keyboard.txt shows localized Information/45B/mode0644; Escape
  closes in final build.
- Command-F, focus query and set Keyboard*, F5 then Escape: closes search without
  background copy or other selected-file change.

Test app quit normally at end. No OS restart, account sign-in, network permission
grant, personal-file edit/deletion, or installed-app replacement.

## Independent final integrity/regression

`verify-keyboard-safety.swift` reads exact original contents, checks Left/Right have
only their original entries, no transfer jobs, and isolated root/DE/dark defaults.
Exit0: `parity-20261023-keyboard-integrity.log`.

Source SHA4dd7ad27a174cded49a9839f356ef071646b1e71fe38ae73335a407ab1b5528c;
sentinel SHA924a3443bd79e5f53b420ab315a79c55d212399ef485669e2e6f7cc8df412c87,
unchanged after tests.

Fresh23-Oct `run-commander-tools-tests.sh`: exit0,18 PASS groups, including actual
controlled rename SIGKILL/restart regression; intentional killed test children
are not application crashes. `run-handbook-tests.sh`: exit0,two PASS groups,
including complete18-topic DE/EN handbook. Logs
`parity-20261023-keyboard-tools.log` and `parity-20261023-keyboard-handbook.log`.
These support the native evidence; they do not replace full manual coverage.

## Remaining matrix

Complete keyboard-only focus/reordering/queue controls, every shortcut variant,
all display scales/resolutions and all local/NAS/cloud dialog prerequisites remain
unproven. Earlier NAS transfers/physical NTFS scopes are separate evidence, not
rerun or inferred here. Overall acceptance/installation goal stays active.
