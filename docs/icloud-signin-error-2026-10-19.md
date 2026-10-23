# Visible iCloud sign-in errors

Recognize Apple's incorrect-credentials text and error code -20101, as well as
the existing HTTP 401/invalid-credentials rejection. Unknown sign-in failures
no longer incorrectly claim missing device verification. All messages remain
sanitized keys, never raw provider output or credential values.

Cloud setup now displays a localized failure alert and red inline status after
an error, announces it for accessibility, clears secret/code fields and retains
the existing new-private-connection retry behavior. Cancellation does not display
an authentication-failure alert. No automatic bad-password retry was added.

Validation: runtime suite with synthetic incorrect-password/code/401/device and
unknown-error responses passed; secret sentinel absent from surfaced errors.
27 localization dictionaries checked; signed Mac build and extension preflight
passed (`icloud-password-error-tests.log`, `icloud-password-error-build.log`).
No deliberately incorrect password was submitted to a live Apple account.

No setup dialog or transfer was active before normal quit. Installed at
`/Applications/OpenCommander.app`; previous app retained at
`.build-native/App-before-install.CYfoUk/OpenCommander.saved`.
After launch, saved direct iCloud location restored and displayed a listing.
This proves listing/auth persistence, not the complete iCloud write/Undo matrix.
Native HelpMoreApps displayed the haenggi.vip link in this installed build.
