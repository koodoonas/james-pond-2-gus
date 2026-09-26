# Analysis checkpoint 01

Date: 2026-09-26

## Exact input release

- Uploaded container SHA-256: `4fd7123132b4b942f1d1fe46ae0965f8490c552e560e8f8c4db6e95fe39697fd`
- The uploaded `.iso` is actually a RAR5 archive.
- Target `ROBOCOD.EXE`: 82,840 bytes, CRC-32 `2fe69840`, SHA-256
  `777a8ca93c3764810ae5162c0007124817e42ede77c9a5e796f407cb367e20b1`.
- The executable is an EXEPACK-style self-unpacking real-mode MZ image.
- Original entry after unpacking: code offset `EA7E`.

## Audio assets

The release contains seven standard 31-instrument four-channel tracker modules:

| File | Signature | Patterns | Sample bytes |
| --- | --- | ---: | ---: |
| `TITLE1` | `FLT4` | 18 | 117,932 |
| `CATLOTS` | `FLT4` | 8 | 67,796 |
| `BATH1` | `FLT4` | 11 | 65,512 |
| `TOYS1` | `FLT4` | 16 | 65,512 |
| `XMAS1` | `FLT4` | 10 | 65,512 |
| `MOD.BON` | `M.K.` | 8 | 40,152 |
| `MOD.ELG` | `M.K.` | 17 | 40,152 |

The pattern payload is 90,112 bytes in total. Physical module sample payloads
total 462,568 bytes (the two `M.K.` files each describe thirteen conventional
two-byte empty instruments whose placeholder bytes are omitted). `SAMPLES.BIN`
is a 29,342-byte signed 8-bit SFX bank containing
29 contiguous samples. Everything required for audio therefore fits in the
target GUS MAX's 1 MiB DRAM without deduplication.

## Stable hooks in the unpacked code segment

- `CA8A`: music request; caller supplies a NUL-terminated filename at `DS:DX`.
- `CAA3`: stop current music.
- `DE3E`: sound-effect request; caller supplies the effect number in `BX`.

The plan is to validate the exact executable before launch, run it without its
Sound Blaster or AdLib switches, and replace only these three entry points in
the child's unpacked memory. The original executable remains unchanged.

## Native GF1 design

- Read and validate `ULTRASND=base,dma1,dma2,irq1,irq2`.
- Preload all seven modules and `SAMPLES.BIN` into GF1 DRAM before starting the
  child process.
- Keep only compact song metadata in conventional memory.
- Use four GF1 voices for music and a rotating pool of voices for SFX.
- Fetch the next 16-byte tracker row from GF1 DRAM at row boundaries; no PCM is
  mixed by the CPU.
- Read the game's own SFX command streams and descriptor tables from the
  unpacked child image at run time. No command streams or original sample data
  are embedded in the patch.
- Use the GF1 timer IRQ for tracker/SFX ticks, preserving and restoring all
  vectors and PIC masks on exit.

## Copyright boundary

The source tree contains no original game bytes or assets. Analysis helpers
take a user-supplied executable at run time. Generated disassemblies, unpacked
images, game files, and third-party tool binaries are excluded from source and
release archives.
