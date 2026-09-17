# Cleaner Safe Rule Calibration

## Scope

This calibration only covers the existing `User Cache`, `Application Cache`,
`Logs`, and `Temporary Files` categories. Only one rule is promoted to
`safe`; the other three categories remain review-required, protected, or
unknown unless their existing evidence is sufficient.

## Calibrated rule

- **Rule ID:** `calibrated-user-cache-fscached-data`
- **Category:** User Cache
- **Path pattern:** `~/Library/Caches/<verified-installed-bundle-id>/fsCachedData/**`
- **Bundle identifier:** The first path component must be an exact bundle ID
  from an installed `.app` in `/Applications` or `~/Applications`.
- **Data use:** Application-generated filesystem cache objects.
- **Regeneration basis:** The owning application can recreate the objects;
  the rule never matches the cache container or its parent bundle directory.
- **Safety evidence:** Exact installed ownership, exact `fsCachedData` scope,
  regular-file requirement, canonical path stability, no symlink components,
  and existing sensitive-path/database protections.
- **Exclusions:** Unknown/uninstalled bundle IDs, symlink or canonical escape,
  identity/source changes, protected paths, directories, sensitive names,
  files newer than 24 hours, and zero-byte files.
- **Age policy:** Older than 24 hours.
- **Size policy:** At least 1 byte.
- **Ownership requirement:** Installed application bundle ID resolution.
- **Confidence:** High, limited to this exact path shape and evidence set.
- **Tests:** Exact ownership, unowned bundle, non-`fsCachedData` path, evidence
  completeness, symlink/source/identity/protected-path rejection, CleanupPlan
  preflight, and controlled Trash E2E.
- **Real validation:** Current-Mac read-only scan, 100 largest safe-candidate
  structured manual inspections, and controlled Trash/reclassification E2E.

## Current-Mac read-only result

The validation run classified 53,245 collected scan items from 40,707 files and
12,538 directories:

- Safe: **277 / 18,928,064 bytes**
- Review required: **14,495 / 1,220,963,087 bytes**
- Protected: **22,781 / 1,757,917,209 bytes**
- Unknown: **15,692 / 3,501,172,586 bytes**

Safe contribution:

- `calibrated-user-cache-fscached-data`: **277 items / 18,928,064 bytes**

The 100 largest safe candidates were manually inspected against the rule
evidence and filesystem identity checks: **100/100 valid; no apparent user-data
misclassification**.

## Controlled destructive-boundary validation

No real user cache was deleted. A controlled fixture was processed through:

`Scan → Classify → CleanupPlan → Dry Run → Preflight → SafeDelete → Audit`

One unchanged file entered Trash, one recreated controlled cache was classified
safe again, and the running Codex application was observed without modifying its
real cache. The result was **pass**, with **16 bytes** reclaimed in the
controlled fixture.

## Performance

- Scan: approximately **1.60 seconds**.
- Classification: approximately **44.84 seconds** for the collected set.
- CPU: approximately **50.94 seconds** process user+system time.
- Peak RSS after per-item autorelease-pool control: approximately **54 MB**.

The classification cost is dominated by conservative per-item canonical,
symlink, protected-path, sensitive-data, and Git ancestry checks. No scan limit
was lowered to increase the safe count.

## Deliberately not calibrated

`Application Cache`, `Logs`, and `Temporary Files` remain non-safe in this
phase. Their current data-use, activity, shared-ownership, session, diagnostic,
and in-use evidence is not strong enough for automatic cleaning.
