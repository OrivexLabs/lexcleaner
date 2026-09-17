#!/usr/bin/env python3
"""Verify a real macOS distribution artifact without creating or signing it.

This is a release prerequisite gate, not a replacement for Apple's signing,
notarization, Sparkle appcast tooling, or a professional security scanner.
It intentionally fails when the local machine cannot prove the artifact.
"""

from __future__ import annotations

import argparse
import base64
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def require_command(name: str, failures: list[str]) -> None:
    if shutil.which(name) is None:
        failures.append(f"required command is unavailable: {name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="exact .app bundle to verify")
    args = parser.parse_args()

    failures: list[str] = []
    for command in ("xcodebuild", "codesign", "spctl", "stapler", "plutil"):
        require_command(command, failures)

    app = args.app
    if app.suffix != ".app" or not app.is_dir():
        failures.append(f"artifact is not an existing .app bundle: {app}")

    identity = run(["security", "find-identity", "-v", "-p", "codesigning"])
    if "Developer ID Application" not in identity.stdout:
        failures.append("no Developer ID Application identity is available")

    info_path = app / "Contents" / "Info.plist"
    try:
        with info_path.open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as exc:
        failures.append(f"cannot read bundle Info.plist: {exc.__class__.__name__}")
        info = {}

    feed = info.get("SUFeedURL")
    if not isinstance(feed, str) or not feed.lower().startswith("https://"):
        failures.append("bundle does not contain an HTTPS SUFeedURL")

    public_key = info.get("SUPublicEDKey")
    try:
        key_data = base64.b64decode(public_key, validate=True) if isinstance(public_key, str) else b""
    except ValueError:
        key_data = b""
    if len(key_data) != 32:
        failures.append("bundle does not contain a valid 32-byte Ed25519 SUPublicEDKey")

    if info.get("SURequireSignedFeed") is not True:
        failures.append("SURequireSignedFeed is not true")
    if info.get("SUVerifyUpdateBeforeExtraction") is not True:
        failures.append("SUVerifyUpdateBeforeExtraction is not true")
    if info.get("SUAutomaticallyUpdate") is not False:
        failures.append("SUAutomaticallyUpdate is not false")

    if not failures:
        codesign = run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)])
        if codesign.returncode != 0:
            failures.append("codesign strict verification failed")

        gatekeeper = run(["spctl", "--assess", "--type", "execute", "--verbose=4", str(app)])
        if gatekeeper.returncode != 0:
            failures.append("Gatekeeper assessment failed")

        stapled = run(["stapler", "validate", str(app)])
        if stapled.returncode != 0:
            failures.append("no valid stapled notarization ticket was proven")

    if failures:
        print("macOS distribution gate: BLOCK")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("macOS distribution gate: PASS")
    print("- exact app bundle passed Developer ID, Gatekeeper, stapling, and Sparkle configuration checks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
