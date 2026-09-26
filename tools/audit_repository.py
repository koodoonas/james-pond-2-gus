#!/usr/bin/env python3
"""Fail if a clean JP2GUS tree contains known game payloads."""

from __future__ import annotations

import hashlib
import argparse
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

FORBIDDEN_NAMES = {
    "robocod.exe",
    "robocod.rnc",
    "samples.bin",
    "title1",
    "catlots",
    "bath1",
    "toys1",
    "xmas1",
    "mod.bon",
    "mod.elg",
}

FORBIDDEN_SHA256 = {
    "777a8ca93c3764810ae5162c0007124817e42ede77c9a5e796f407cb367e20b1",
    "176c9befe643611e1ac53eb1a57a6e330dbeece793efd97bd2bbee3259835039",
    "5b9f2b5b5395187d0bcd0235e0d3a020f586adef10f1bb037e2d20227cca4a6a",
    "321ded9d67328664eb6e6f58866e93876e6e148462514f3d18a36d65fe3ded64",
    "b23882e1c1d720b90de6560b6a0bcfc44a6a11168d05c7c9268572df6051af31",
    "6092d600ebabda0cb5c45933c789ac53169e9d453a3b240a54e16bc1490aaea5",
    "8372d6899fee7e508d519eaa39fada7737cba9bb8958c7ce50831e1c6a7af2d7",
    "4cd459da767cb4a9fc4375ac865eb4b91dd9efc7ddf1878184e7f7208b32b583",
    "3abcf69608ee2da0043e325f761e68699840f362e22ce82142066d6168936701",
    "96c55dbc3d618c98463f2919a486be6d20e606ecc5c9a9d234da5f5e6c1e973c",
}


def project_files() -> list[Path]:
    excluded = {".git", "test-work", "dist", "__pycache__"}
    return [
        path
        for path in sorted(ROOT.rglob("*"))
        if path.is_file() and not any(part in excluded for part in path.relative_to(ROOT).parts)
    ]


def informative(chunk: bytes) -> bool:
    # Interoperability strings such as required filenames are facts, not game
    # code or media.  The overlap check targets opaque binary sequences.
    if all(value == 0 or 0x20 <= value <= 0x7E for value in chunk):
        return False
    return len(set(chunk)) >= 6 and max(chunk.count(value) for value in set(chunk)) <= 36


def audit_overlap(paths: list[Path], reference_dir: Path) -> list[str]:
    reference_names = FORBIDDEN_NAMES - {"robocod.exe"} | {"robocod.exe"}
    references = [
        path.read_bytes()
        for path in reference_dir.iterdir()
        if path.is_file() and path.name.lower() in reference_names
    ]
    width = 48
    fingerprints: set[int] = set()
    for payload in references:
        for offset in range(len(payload) - width + 1):
            chunk = payload[offset : offset + width]
            if informative(chunk):
                fingerprints.add(zlib.crc32(chunk))

    failures: list[str] = []
    for path in paths:
        payload = path.read_bytes()
        for offset in range(len(payload) - width + 1):
            chunk = payload[offset : offset + width]
            if not informative(chunk):
                continue
            if zlib.crc32(chunk) in fingerprints and any(chunk in ref for ref in references):
                failures.append(
                    f"48-byte sequence from game payload: {path.relative_to(ROOT)}+0x{offset:x}"
                )
                break
    return failures


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference-dir", type=Path)
    args = parser.parse_args()
    failures: list[str] = []
    paths = project_files()
    for path in paths:
        relative = path.relative_to(ROOT)
        if path.name.lower() in FORBIDDEN_NAMES:
            failures.append(f"forbidden game filename: {relative}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest in FORBIDDEN_SHA256:
            failures.append(f"known game payload: {relative}")
        if path.suffix.lower() == ".asm" and b"incbin" in path.read_bytes().lower():
            failures.append(f"binary inclusion directive: {relative}")
    if args.reference_dir:
        failures.extend(audit_overlap(paths, args.reference_dir.resolve()))
    if failures:
        raise SystemExit("copyright audit failed:\n  " + "\n  ".join(failures))
    print("copyright audit passed: no known game executable or audio payloads")


if __name__ == "__main__":
    main()
