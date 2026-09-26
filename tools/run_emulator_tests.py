#!/usr/bin/env python3
"""Run the GF1 self-test and child-hook test without retaining game files."""

from __future__ import annotations

import argparse
import array
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[1]
REQUIRED = (
    "ROBOCOD.EXE",
    "ROBOCOD.RNC",
    "SAMPLES.BIN",
    "TITLE1",
    "CATLOTS",
    "BATH1",
    "TOYS1",
    "XMAS1",
    "MOD.BON",
    "MOD.ELG",
)

CONFIG = r"""
[sdl]
fullscreen=false
output=surface
autolock=false

[dosbox]
machine=svga_s3
memsize=16

[render]
frameskip=0
aspect=false
scaler=none

[cpu]
core=normal
cputype=386_slow
cycles=fixed 8000

[mixer]
nosound=false
rate=44100
blocksize=1024
prebuffer=20

[midi]
mpu401=none
mididevice=none

[sblaster]
sbtype=none

[gus]
gus=true
gusrate=44100
gusbase=240
gusirq=7
gusdma=7
ultradir=C:\ULTRASND

[speaker]
pcspeaker=false
tandy=off
disney=false

[joystick]
joysticktype=none

[autoexec]
mount c .
c:
set ULTRASND=240,7,7,7,7
{command} > {log_name}
exit
""".strip()


def audio_metrics(path: Path) -> dict[str, float | int]:
    pcm = array.array("h")
    pcm.frombytes(path.read_bytes())
    if sys.byteorder != "little":
        pcm.byteswap()
    if not pcm:
        raise RuntimeError("DOSBox produced an empty PCM capture")
    squares = sum(sample * sample for sample in pcm)
    left = pcm[0::2]
    right = pcm[1::2]
    left_squares = sum(sample * sample for sample in left)
    right_squares = sum(sample * sample for sample in right)
    difference_squares = sum((lhs - rhs) ** 2 for lhs, rhs in zip(left, right))
    return {
        "bytes": path.stat().st_size,
        "nonzero_percent": round(100 * sum(sample != 0 for sample in pcm) / len(pcm), 2),
        "peak": max(abs(sample) for sample in pcm),
        "rms": round((squares / len(pcm)) ** 0.5, 2),
        "left_rms": round((left_squares / len(left)) ** 0.5, 2),
        "right_rms": round((right_squares / len(right)) ** 0.5, 2),
        "stereo_difference_rms": round((difference_squares / len(left)) ** 0.5, 2),
        "clipped_samples": sum(abs(sample) >= 32760 for sample in pcm),
    }


def run_case(
    work: Path,
    dosbox: Path,
    library_dir: Path | None,
    name: str,
    switch: str,
    expected: str,
) -> dict[str, object]:
    log_name = f"{name}.LOG"
    config = work / f"{name}.conf"
    config.write_text(CONFIG.format(command=f"JP2GUS {switch}", log_name=log_name))
    audio = work / f"{name}.raw"
    env = os.environ.copy()
    env.update(
        {
            "SDL_VIDEODRIVER": "dummy",
            "SDL_AUDIODRIVER": "disk",
            "SDL_DISKAUDIOFILE": str(audio),
        }
    )
    if library_dir:
        old = env.get("LD_LIBRARY_PATH")
        env["LD_LIBRARY_PATH"] = str(library_dir) + ((":" + old) if old else "")
    completed = subprocess.run(
        [str(dosbox), "-conf", config.name, "-noconsole"],
        cwd=work,
        env=env,
        timeout=45,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    log = (work / log_name).read_text(errors="replace").replace("\r", "")
    if completed.returncode != 0 or expected not in log:
        raise RuntimeError(
            f"{name} failed (exit {completed.returncode})\nDOS log:\n{log}\nHost log:\n{completed.stdout}"
        )
    metrics = audio_metrics(audio)
    if metrics["nonzero_percent"] < 1 or metrics["peak"] < 100:
        raise RuntimeError(f"{name} produced silence or near-silence: {metrics}")
    if metrics["stereo_difference_rms"] < 10:
        raise RuntimeError(f"{name} unexpectedly produced mono output: {metrics}")
    return {"log": log.strip(), "audio": metrics}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--game-dir", type=Path, required=True)
    parser.add_argument("--dosbox", type=Path, required=True)
    parser.add_argument("--library-dir", type=Path)
    parser.add_argument(
        "--results", type=Path, default=PROJECT / "build" / "emulator-test-results.json"
    )
    args = parser.parse_args()
    args.game_dir = args.game_dir.resolve()
    args.dosbox = args.dosbox.resolve()
    if args.library_dir:
        args.library_dir = args.library_dir.resolve()
    args.results = args.results.resolve()

    binary = PROJECT / "build" / "JP2GUS.COM"
    if not binary.is_file():
        raise SystemExit("build/JP2GUS.COM is missing; run make first")
    missing = [name for name in REQUIRED if not (args.game_dir / name).is_file()]
    if missing:
        raise SystemExit("game directory is missing: " + ", ".join(missing))

    with tempfile.TemporaryDirectory(prefix="jp2gus-test-") as temporary:
        work = Path(temporary)
        for name in REQUIRED:
            shutil.copy2(args.game_dir / name, work / name)
        shutil.copy2(binary, work / "JP2GUS.COM")
        results = {
            "configuration": "ULTRASND=240,7,7,7,7; 386_slow; 8000 cycles; GF1 44.1 kHz",
            "selftest": run_case(
                work, args.dosbox, args.library_dir, "SELFTEST", "/T", "Self-test passed"
            ),
            "integration": run_case(
                work,
                args.dosbox,
                args.library_dir,
                "INTEG",
                "/X",
                "in-memory hooks removed",
            ),
        }

    args.results.parent.mkdir(parents=True, exist_ok=True)
    args.results.write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
