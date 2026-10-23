# Per-pane online location restoration

Implemented connection and nested directory restoration after normal app restart.
Navigation records contain only a location reference and validated folder names,
not credentials, configuration paths or provider session IDs. Each pane has its
own record. Navigation saves only after a successful listing; explicit return to
local and local location changes clear the online record. Missing connections
fall back to the existing local location. Missing/ambiguous directories produce
localized guidance and a subsequent refresh opens the connection root.

On startup, folder names resolve through fresh listings rather than stale IDs.
Both pane instances can restore independently. Existing saved authentication is
used; no unattended new login or expanded permission grant is performed.

Evidence:
- 12 runtime test groups passed (`online-session-runtime.log`), including isolated
  preferences roundtrip, per-pane separation, Unicode, malformed reference and
  path traversal/control-character refusal, and credential-free schema.
- Native build and extension signature checks passed (`online-session-build.log`).
- Native Dropbox navigation to own `OpenCommander-LiveQA-Size12-wUvOA0/Sub`,
  normal quit/restart: exact path and b.txt restored without sign-in.
- Second native quit/restart with Dropbox/Sub left and Google QA folder right:
  both exact paths and expected b.txt/a.txt appeared. No cloud files mutated.

Linux reference fetched again: origin/codex/linux-desktop e3b2981. This closes a
specific navigation gap, not the complete 158-case parity acceptance. WebDAV and
service/environment-dependent cases remain open. Full cloud regression and
installation status are recorded below when completed.

Full cloud regression completed: 69 PASS groups (`online-session-clients.log`).
Installed the tested signed bundle and verified startup at
`/Applications/OpenCommander.app`. Previous version remains recoverable in
`.build-native/App-before-install.BTPG1v/OpenCommander.saved`.
