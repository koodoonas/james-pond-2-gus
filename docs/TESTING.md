# Verification record

Date: 2026-09-26

## Version 1.0 hardware status

Version 1.0 was reported working during gameplay on the target physical 386
and GUS MAX. The report confirms the complete build but did not itemize every
joystick, pan, volume, or diagnostic switch combination.

No additional unit, audit, or DOSBox run was performed for the final version,
by request. The detailed automated results below are the preserved version 0.9
baseline and are not presented as version 1.0 test results.

## Version 0.9 static and asset checks

Six unit tests validate the exact executable identity, all seven module
layouts, physical sample lengths, the 1 MiB DRAM budget, the complete tracker
effect subset, build format, hook offsets, and `ULTRASND` contract.

The clean-tree audit rejects known game payload hashes and, when given the game
directory, compares every nontrivial 48-byte binary window in the project with
the executable and audio assets. Interoperability strings such as filenames are
excluded from that byte-overlap check.

## Version 0.9 DOSBox GF1 tests

Configuration:

- CPU: `386_slow`, fixed 8,000 cycles
- GUS: base `240`, IRQ `7`, DMA `7`, 44.1 kHz
- DOS environment: `ULTRASND=240,7,7,7,7`
- Sound Blaster, MIDI, PC speaker, and joystick disabled

Automated results:

| Case | Result | Songs | SFX notes | PCM nonzero | Peak | RMS | Stereo-difference RMS | Clipped |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `/T` GF1 self-test | Pass | 1 | 1 | 64.85% | 21,338 | 4,488.70 | 1,579.25 | 0 |
| `/I` child integration (0.9 behavior) | Pass | 1 | 7 | 64.47% | 23,852 | 2,716.83 | 1,555.67 | 0 |

The 0.9 integration case verifies that the packed child reaches its exact unpack
handoff, receives all three in-memory hooks, requests title music, interprets a
real SFX command stream, terminates, and returns with interrupt vectors and the
GUS interface restored.

The current harness uses an internal-only `/X` switch to retain that bounded
automation. User-facing `/I` now runs the game normally and only reports event
counters after the player exits.

Reproduce with:

```sh
make verify \
  GAME_DIR=/path/to/original/game \
  DOSBOX=/path/to/dosbox \
  DOSBOX_LIB_DIR=/optional/path/to/dosbox/libs
```

The harness copies game files only into an automatically deleted temporary
directory. It retains a JSON metrics report at
`build/emulator-test-results.json`; captured PCM and game files are discarded.

## Physical-hardware status

The version 0.9 audio path and the complete version 1.0 build were subsequently
reported working during gameplay on the physical 386 and GUS MAX. The 1.0
report did not enumerate every command-line permutation.
