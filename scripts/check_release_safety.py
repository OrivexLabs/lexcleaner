#!/usr/bin/env python3
"""Run a bounded, repository-only release safety scan.

This is a guardrail, not a replacement for a dedicated secret scanner,
dependency audit, malware analysis, or manual license review.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


PATTERNS = (
    ("private key", re.compile(rb"-----BEGIN [^-]*PRIVATE KEY-----")),
    ("AWS access key", re.compile(rb"\bAKIA[0-9A-Z]{16}\b")),
    ("GitHub token", re.compile(rb"\bgh[pousr]_[A-Za-z0-9_]{20,}\b")),
    ("OpenAI-style token", re.compile(rb"\bsk-[A-Za-z0-9]{20,}\b")),
    ("personal path", re.compile(rb"/Users/z(?:/|$)")),
    ("Codex private path", re.compile(rb"/Users/[^/]+/\.codex(?:/|$)")),
)


def tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z"], check=True, stdout=subprocess.PIPE
    )
    return [Path(item.decode("utf-8")) for item in result.stdout.split(b"\0") if item]


def main() -> int:
    findings: list[tuple[str, str]] = []
    for path in tracked_files():
        try:
            content = path.read_bytes()
        except OSError as exc:
            findings.append((str(path), f"unreadable tracked file ({exc.__class__.__name__})"))
            continue
        if b"\0" in content:
            continue
        for label, pattern in PATTERNS:
            if pattern.search(content):
                findings.append((str(path), label))

    if findings:
        print("release safety scan: BLOCK")
        for path, label in findings:
            print(f"- {path}: {label}")
        return 1

    print(f"release safety scan: PASS ({len(tracked_files())} tracked files checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
