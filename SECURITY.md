# Security Policy

LexCleaner is a local macOS utility. Reports and diagnostics must not expose
passwords, tokens, private keys, full user paths, or private network details.
The cleanup engine is intentionally fail-closed and moves selected items to
Trash; it does not provide a permanent-delete or privileged-helper API.

The Network page reads public Network.framework/SystemConfiguration state and
performs bounded TCP/DNS probes only when the user opens or invokes those
features. DNS changes are a separate high-risk path: they require an explicit
confirmation, administrator authorization, an exact current-configuration
match, post-change verification, and an attempted verified rollback on failure.
The recovery journal is local application data; it is not uploaded or included
in diagnostic reports. See `PRIVACY.md` for the complete data inventory.

Sparkle is fail-closed until the build contains an HTTPS feed and a valid
Ed25519 public key. An update candidate whose archive signature is not verified
is rejected by the App adapter. Release builds must additionally pass the
Developer ID, notarization, stapling, and appcast-signature checks documented in
`Updates/README.md`.

## Reporting a vulnerability

Please do not publish sensitive details in a public issue. Contact the
maintainers privately through the repository's configured GitHub security
contact. Include a minimal reproduction, affected commit, macOS version, and
impact. Do not attach credentials or personal diagnostic dumps.

This repository does not promise a response time or a supported release
timeline. A report is not an authorization to test against another person's
device or data.
