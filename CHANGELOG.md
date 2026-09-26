# Changelog

## 1.0 - 2026-09-26

- Enable the game's joystick mode by default, with `/J` and `/NJ` overrides.
- Add signed music stereo-width control with `/P-100..100`.
- Add `/M0..100` music and `/S0..100` sound-effects volume controls.
- Change `/I` into a normal, non-blocking launch that reports GF1 event counts
  only after the game exits.
- Keep the 50 Hz sequencer and all PCM mixing on the GF1; option conversion is
  done during launcher startup.

The complete build was subsequently reported working during gameplay on the
target physical 386/GUS MAX. Individual command-line combinations were not
itemized in the hardware report.

## 0.9 - 2026-09-26

- Initial clean-room native GF1 launcher with music and sound effects.
- Preload all audio into 1 MiB GUS RAM and use fourteen hardware voices.
- Add exact-release validation, transient in-memory hooks, and `ULTRASND`
  configuration.
