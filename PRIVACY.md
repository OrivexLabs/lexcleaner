# Privacy and data boundaries

LexCleaner is a local-first macOS utility. It does not include an analytics
SDK, telemetry endpoint, crash-upload service, or background data export. No
scan result, file content, diagnostic report, or network measurement is sent
to the maintainers automatically.

## What the app reads

Only the feature the user invokes reads its required state:

- **Cleaner and Disk Analyzer:** file metadata, directory structure, symlink
  relationships, and bounded paths under the selected user-accessible roots.
  The engines do not read file contents to classify cleanup candidates.
- **App Manager:** discoverable `.app` bundle metadata and exact,
  bundle-identifier-derived residual locations. Shared or uncertain data is
  retained as review/unknown rather than treated as safe.
- **System Tools:** public launch-item declarations, public permission status
  APIs, and capability results. The app does not inspect TCC databases or
  infer Full Disk Access from a failed file probe.
- **Monitoring and Hardware:** public process, memory, CPU, storage, thermal,
  battery, and interface counters when the operating system exposes them.
- **Network:** public Network.framework/SystemConfiguration state. TCP and DNS
  probes run only when the user opens the Network page or starts a benchmark;
  they are bounded probes, not packet-loss or VPN-proof claims.
- **Diagnostics:** version/build, public OS/model/architecture values, module
  states, a bounded in-memory error ring, and the count/date of matching local
  crash reports. Error text is redacted before it enters the report.

## What the app writes

- Language and appearance preferences are stored in app preferences.
- Selected cleanup items are moved to the system Trash only after Dry Run,
  explicit confirmation, and preflight checks. The app has no permanent-delete
  or privileged-helper API.
- A DNS change is never automatic. After explicit confirmation and administrator
  authorization, the app writes the selected system DNS configuration and
  stores a local recovery record at the standard Application Support location.
  The record contains the original/proposed DNS transaction and configuration
  snapshot so rollback can be verified. It is not uploaded or put in reports.
- User-initiated diagnostic copy/export writes only to the destination chosen
  by the user. Feedback opens GitHub in the browser; it does not upload a
  report automatically.
- Sparkle may use the configured HTTPS feed only in a distribution build with
  a valid Ed25519 public key. It does not silently install updates; failed
  feed, signature, extraction, or installation validation keeps the current
  app.

## Permissions and control

Permission status is queried without requesting access. Camera, microphone,
Accessibility, and Screen Recording are reported as authorized, denied,
not-determined, unavailable, or unsupported where the public API permits that
distinction. Full Disk Access is explicitly reported as unsupported because
the app does not inspect private TCC databases. The app does not ask for root
or silently modify permissions.

## Retention and deletion

The diagnostic error ring is bounded in memory and is not a durable telemetry
store. The DNS recovery record remains only while a transaction needs recovery
or rollback and is cleared after a verified reconciliation. App preferences
and normal macOS Trash retention follow the operating system; users can remove
the app's preferences and Trash contents using standard macOS controls.

This document describes the current implementation boundary. A signed release
must be re-audited against the exact artifact and its actual entitlements,
Sparkle feed, and notarization result.
