# JP2GUS

Clean-room native Gravis UltraSound GF1 music and sound-effects support for one
specific DOS release of *James Pond 2: Codename RoboCod*.

JP2GUS is a launcher, not a modified game executable. It verifies the exact
`ROBOCOD.EXE`, preloads the user's existing music and sound data into GUS RAM,
then replaces three audio functions only in the running process. The game file
is never changed.

## Why this build is fast

- Four GF1 voices play tracker music and ten rotating GF1 voices play effects.
- Fourteen active voices retain the original GF1's 44.1 kHz mixing rate.
- The 50 Hz GF1 timer drives sequencing without changing the game's PIT timing.
- All seven songs and the complete effect bank are loaded into the card's 1 MiB
  RAM before play; there is no run-time audio disk I/O.
- The CPU decodes tracker rows and compact effect commands only. It never mixes
  PCM samples.

## Exact supported release

`ROBOCOD.EXE` must be 82,840 bytes with:

```
SHA-256 777a8ca93c3764810ae5162c0007124817e42ede77c9a5e796f407cb367e20b1
CRC-32  2fe69840
```

The launcher also expects `SAMPLES.BIN`, `TITLE1`, `CATLOTS`, `BATH1`,
`TOYS1`, `XMAS1`, `MOD.BON`, and `MOD.ELG` beside the executable.

## Build and use

NASM 2.x and a 386 or newer are required.

```sh
make
```

Copy `build/JP2GUS.COM` into the game directory. On the target GUS MAX:

```bat
SET ULTRASND=240,7,7,7,7
JP2GUS /T
JP2GUS
```

Joystick control is enabled by default: the launcher gives the game its `+J`
argument automatically. The default mix is music 75%, effects 81%, and normal
stereo width 60%. For example:

```bat
JP2GUS /NJ /P0 /M70 /S85
JP2GUS /P-60
JP2GUS /I
```

| Switch | Effect |
| --- | --- |
| `/J` | Enable joystick (the default) |
| `/NJ` | Disable joystick |
| `/P-100..100` | Set stereo width; `0` centers music, positive is normal, negative reverses left/right |
| `/M0..100` | Set music volume percentage |
| `/S0..100` | Set sound-effects volume percentage |
| `/I` | Launch normally and print GF1 music/SFX event counters after the game exits |
| `/T` | Run the five-second GF1 hardware self-test instead of the game |

`=`, `:`, and an explicit plus sign are accepted, so `/M=75`, `/S:81`, and
`/P+60` are equivalent forms. Mixer percentages and stereo positions are
converted to GF1 register values once at launch; PCM remains entirely on the
hardware mixer.

Do not add the game's `+S` or `+A` switches; JP2GUS owns the audio path.

## Tested hardware

Version 1.0 has been successfully tested during gameplay on:

- A physical 386 with a GUS MAX.
- A physical 486/133 with a Gravis UltraSound PnP.

It adds the command-line controls above and changes `/I` to a non-blocking
diagnostic launch. The hardware reports covered the complete build but did not
itemize every possible command-line combination.

## Verification

```sh
make test GAME_DIR=/path/to/game
make audit GAME_DIR=/path/to/game
make emutest GAME_DIR=/path/to/game DOSBOX=/path/to/dosbox
```

See [docs/TESTING.md](docs/TESTING.md) for the captured test results and the
optional DOSBox shared-library argument.

## Other GUS Patches

[Gravis Ultrasound Game Patches](https://github.com/koodoonas/gus-game-patches-and-fixes)

## AI usage disclosure

These patches have been heavily assisted by AI and, in some cases, developed almost entirely with its help.

I remain ambivalent about AI and its human and environmental costs. But since it’s already here, I might as well use it for something fun until it consumes us all.

## Copyright boundary

This repository and its release archives contain original patch code and
factual compatibility metadata only. They contain no game executable bytes,
music, samples, graphics, text, disassembly, or vendor SDK code. The audit can
compare every nontrivial 48-byte binary sequence against the user's game files.

You must supply your own legally obtained game files. JP2GUS is not affiliated
with the game's rights holders or with Advanced Gravis.
