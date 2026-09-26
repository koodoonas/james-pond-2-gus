#!/usr/bin/env python3
"""Create deterministic clean source and binary archives."""

from __future__ import annotations

import hashlib
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
VERSION = "1.0"
STAMP = (2026, 9, 26, 0, 0, 0)

SOURCE_FILES = (
    ".gitignore",
    "CHANGELOG.md",
    "LICENSE",
    "Makefile",
    "README.md",
    "README-DOS.TXT",
    "requirements-analysis.txt",
    "src/jp2gus.asm",
    "docs/ANALYSIS.md",
    "docs/TESTING.md",
    "tests/test_release_contract.py",
    "tools/audit_repository.py",
    "tools/map_code.py",
    "tools/run_emulator_tests.py",
    "tools/unpack_exepack.py",
    "tools/package_release.py",
)


def add_bytes(archive: zipfile.ZipFile, name: str, payload: bytes, executable: bool = False) -> None:
    info = zipfile.ZipInfo(name, STAMP)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.create_system = 3
    info.external_attr = ((0o755 if executable else 0o644) & 0xFFFF) << 16
    archive.writestr(info, payload)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    binary = ROOT / "build" / "JP2GUS.COM"
    if not binary.is_file():
        raise SystemExit("build/JP2GUS.COM is missing; run make first")
    DIST.mkdir(parents=True, exist_ok=True)

    binary_zip = DIST / f"JP2GUS-{VERSION}-binary.zip"
    prefix = f"JP2GUS-{VERSION}/"
    sums = f"{sha256(binary)}  JP2GUS.COM\n".encode()
    with zipfile.ZipFile(binary_zip, "w") as archive:
        add_bytes(archive, prefix + "JP2GUS.COM", binary.read_bytes())
        add_bytes(archive, prefix + "README-DOS.TXT", (ROOT / "README-DOS.TXT").read_bytes())
        add_bytes(archive, prefix + "CHANGELOG.md", (ROOT / "CHANGELOG.md").read_bytes())
        add_bytes(archive, prefix + "TESTING.md", (ROOT / "docs" / "TESTING.md").read_bytes())
        add_bytes(archive, prefix + "LICENSE", (ROOT / "LICENSE").read_bytes())
        add_bytes(archive, prefix + "SHA256SUMS", sums)

    source_zip = DIST / f"JP2GUS-{VERSION}-source.zip"
    source_prefix = f"JP2GUS-{VERSION}-source/"
    with zipfile.ZipFile(source_zip, "w") as archive:
        for relative in SOURCE_FILES:
            path = ROOT / relative
            add_bytes(
                archive,
                source_prefix + relative,
                path.read_bytes(),
                executable=relative.startswith("tools/") and relative.endswith(".py"),
            )

    manifest = DIST / "SHA256SUMS.txt"
    manifest.write_text(
        f"{sha256(binary_zip)}  {binary_zip.name}\n"
        f"{sha256(source_zip)}  {source_zip.name}\n"
    )
    print(binary_zip)
    print(source_zip)
    print(manifest)


if __name__ == "__main__":
    main()
