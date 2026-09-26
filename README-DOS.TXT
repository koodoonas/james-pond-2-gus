JP2GUS 1.0 - native Gravis UltraSound audio for James Pond 2
===============================================================

REQUIREMENTS

* 386 or newer
* Gravis UltraSound with 1 MiB RAM (GUS MAX supported)
* The exact supported ROBOCOD.EXE, size 82,840 bytes
* The game's original SAMPLES.BIN and seven music files

INSTALL

Copy JP2GUS.COM into the directory that contains ROBOCOD.EXE.
The launcher does not alter any game file.

For the requested DFI/GUS MAX configuration, use:

  SET ULTRASND=240,7,7,7,7

First run the five-second hardware test:

  JP2GUS /T

Then launch the game:

  JP2GUS

Joystick use is ON by default. JP2GUS passes +J to the game.

OPTIONS

  /J          joystick on (default)
  /NJ         joystick off
  /P-100..100 music stereo width: 0=center, negative=reversed
  /M0..100    music volume percent (default 75)
  /S0..100    sound-effects volume percent (default 81)
  /I          normal launch; show GF1 event counts when game exits
  /T          five-second GUS hardware self-test; do not launch game

Examples:

  JP2GUS /NJ /P0 /M70 /S85
  JP2GUS /P-60

The default pan is +60. Values may also use = or :, such as /M=75.

Do not use the game's +S or +A switches. JP2GUS supplies both music
and sound effects through the GF1 hardware mixer.

DIAGNOSTIC

  JP2GUS /I

This launches the game normally, checks that the in-memory hooks were
installed, and prints music and sound-effect event counts after you exit.
It no longer waits five seconds or forces the game to terminate.

RELEASE STATUS

Version 1.0 was reported working during gameplay on a physical 386 and
GUS MAX. Individual command-line combinations were not itemized in the
hardware report.

FILES NOT INCLUDED

No game executable, music, sound, graphics, text, or other game data
is included. You must provide your own legally obtained game files.
