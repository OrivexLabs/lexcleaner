# Contributing

## Before opening a change

1. Read `AGENTS.md`, `ARCHITECTURE.md`, and the relevant acceptance notes.
2. Keep cleanup and system integration fail-closed. Do not add permanent-delete,
   privileged-helper, or silent startup mutation paths.
3. Add regression coverage for behavior changes and keep user-facing limits
   explicit instead of inferring unsupported data.

## Local verification

```sh
python3 scripts/check_release_safety.py
swift test
swift build -c release
```

Changes to the Xcode application should also be checked with the project
scheme in a full Xcode environment. Do not include `.build`, `DerivedData`,
diagnostic dumps, credentials, or user-specific paths in a commit.

## Pull requests

Describe the behavior change, safety impact, compatibility considerations,
and the commands actually run. Do not report tests, benchmarks, or runtime
observations that were not executed for the submitted commit.
