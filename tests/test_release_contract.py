from __future__ import annotations

import hashlib
import os
import re
import unittest
import zlib
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get("JP2_GAME_DIR", PROJECT.parent / "source"))

SONGS = {
    "TITLE1": (b"FLT4", 18, 117_932),
    "CATLOTS": (b"FLT4", 8, 67_796),
    "BATH1": (b"FLT4", 11, 65_512),
    "TOYS1": (b"FLT4", 16, 65_512),
    "XMAS1": (b"FLT4", 10, 65_512),
    "MOD.BON": (b"M.K.", 8, 40_152),
    "MOD.ELG": (b"M.K.", 17, 40_152),
}

SUPPORTED_EFFECTS = {0x0, 0x2, 0xA, 0xC, 0xD, 0xF}


@unittest.skipUnless(GAME.is_dir(), "set JP2_GAME_DIR to the legally obtained game directory")
class ReleaseContractTests(unittest.TestCase):
    def test_exact_executable(self) -> None:
        payload = (GAME / "ROBOCOD.EXE").read_bytes()
        self.assertEqual(len(payload), 82_840)
        self.assertEqual(zlib.crc32(payload), 0x2FE69840)
        self.assertEqual(
            hashlib.sha256(payload).hexdigest(),
            "777a8ca93c3764810ae5162c0007124817e42ede77c9a5e796f407cb367e20b1",
        )

    def test_sfx_bank_size(self) -> None:
        self.assertEqual((GAME / "SAMPLES.BIN").stat().st_size, 29_342)

    def test_module_formats_and_dram_budget(self) -> None:
        total_patterns = 0
        total_samples = 0
        for name, (signature, patterns, sample_bytes) in SONGS.items():
            data = (GAME / name).read_bytes()
            self.assertGreaterEqual(len(data), 1084)
            self.assertEqual(data[1080:1084], signature)
            song_length = data[950]
            self.assertIn(song_length, range(1, 129))
            actual_patterns = max(data[952:1080]) + 1
            self.assertEqual(actual_patterns, patterns)
            encoded_lengths = [
                int.from_bytes(data[20 + i * 30 + 22 : 20 + i * 30 + 24], "big") * 2
                for i in range(31)
            ]
            lengths = [length if length > 2 else 0 for length in encoded_lengths]
            self.assertEqual(sum(lengths), sample_bytes)
            self.assertEqual(len(data), 1084 + patterns * 1024 + sample_bytes)
            self.assertTrue(all(data[20 + i * 30 + 24] == 0 for i in range(31)))
            total_patterns += patterns * 1024
            total_samples += sample_bytes
        used = 29_342 + total_patterns + total_samples + 256
        self.assertEqual(used, 582_278)
        self.assertLess(used, 1024 * 1024)

    def test_tracker_effect_subset_is_complete(self) -> None:
        observed: set[int] = set()
        for name in SONGS:
            data = (GAME / name).read_bytes()
            count = max(data[952:1080]) + 1
            patterns = data[1084 : 1084 + count * 1024]
            for offset in range(0, len(patterns), 4):
                effect = patterns[offset + 2] & 0x0F
                parameter = patterns[offset + 3]
                if effect or parameter:
                    observed.add(effect)
                if effect == 0xF:
                    self.assertLessEqual(parameter, 0x1F, "BPM-mode Fxx is not implemented")
        self.assertEqual(observed, SUPPORTED_EFFECTS)


class BuildContractTests(unittest.TestCase):
    def test_binary_is_com_sized(self) -> None:
        binary = PROJECT / "build" / "JP2GUS.COM"
        self.assertTrue(binary.is_file(), "run make first")
        self.assertLess(binary.stat().st_size, 65_280)
        self.assertNotEqual(binary.read_bytes()[:2], b"MZ")

    def test_hook_and_config_contract_in_source(self) -> None:
        source = (PROJECT / "src" / "jp2gus.asm").read_text()
        expected = {
            "PATCH_MUSIC_OFF": "0CA8Ah",
            "PATCH_STOP_OFF": "0CAA3h",
            "PATCH_SFX_OFF": "0DE3Eh",
            "UNPACK_RETURN_IP": "0EAA4h",
            "SOUND_SEG_DELTA": "01EC5h",
        }
        for symbol, value in expected.items():
            self.assertRegex(source, rf"%define\s+{symbol}\s+{value}\b")
        self.assertIn("ultrasnd_key      db 'ULTRASND='", source)
        self.assertNotRegex(source.lower(), r"\bincbin\b")


if __name__ == "__main__":
    unittest.main()
