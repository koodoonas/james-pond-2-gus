#!/usr/bin/env python3
"""Execute an EXEPACK-style DOS loader in a 16-bit CPU sandbox and dump it.

This is an analysis helper, not part of the game patch.  It does not contain
any bytes from the target program.  The input executable is supplied by the
user at run time.
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

from unicorn import Uc, UC_ARCH_X86, UC_HOOK_CODE, UC_MODE_16
from unicorn.x86_const import (
    UC_X86_REG_CS,
    UC_X86_REG_DS,
    UC_X86_REG_ES,
    UC_X86_REG_IP,
    UC_X86_REG_SP,
    UC_X86_REG_SS,
)


MZ_FIELDS = (
    "magic",
    "last_page_bytes",
    "pages",
    "relocations",
    "header_paragraphs",
    "minimum_allocation",
    "maximum_allocation",
    "initial_ss",
    "initial_sp",
    "checksum",
    "initial_ip",
    "initial_cs",
    "relocation_offset",
    "overlay",
)


def read_word(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--load-segment", type=lambda value: int(value, 0), default=0x1010)
    parser.add_argument("--dump-bytes", type=lambda value: int(value, 0), default=None)
    args = parser.parse_args()

    packed = args.input.read_bytes()
    if len(packed) < 32:
        raise SystemExit("input is too short for an MZ executable")

    header_values = struct.unpack_from("<14H", packed)
    header = dict(zip(MZ_FIELDS, header_values))
    if header["magic"] != 0x5A4D:
        raise SystemExit("input does not begin with an MZ header")
    if header["relocations"] != 0:
        raise SystemExit("helper expects the relocation-free EXEPACK loader form")

    header_bytes = header["header_paragraphs"] * 16
    loader_cs = header["initial_cs"]
    loader_metadata = header_bytes + loader_cs * 16
    original_sp = read_word(packed, loader_metadata + 0x13C)
    original_ss = read_word(packed, loader_metadata + 0x13E)
    original_ip = read_word(packed, loader_metadata + 0x140)
    original_cs = read_word(packed, loader_metadata + 0x142)

    load_segment = args.load_segment
    psp_segment = load_segment - 0x10
    if psp_segment < 0:
        raise SystemExit("load segment must be at least 0x10")

    memory_size = 2 * 1024 * 1024
    emu = Uc(UC_ARCH_X86, UC_MODE_16)
    emu.mem_map(0, memory_size)
    image = packed[header_bytes:]
    emu.mem_write(load_segment << 4, image)

    emu.reg_write(UC_X86_REG_CS, load_segment + header["initial_cs"])
    emu.reg_write(UC_X86_REG_IP, header["initial_ip"])
    emu.reg_write(UC_X86_REG_SS, load_segment + header["initial_ss"])
    emu.reg_write(UC_X86_REG_SP, header["initial_sp"])
    emu.reg_write(UC_X86_REG_DS, psp_segment)
    emu.reg_write(UC_X86_REG_ES, psp_segment)

    target_cs = (load_segment + original_cs) & 0xFFFF
    target_ip = original_ip
    stopped = False

    def on_code(uc: Uc, _address: int, _size: int, _user_data: object) -> None:
        nonlocal stopped
        cs = uc.reg_read(UC_X86_REG_CS)
        ip = uc.reg_read(UC_X86_REG_IP)
        if cs == target_cs and ip == target_ip:
            stopped = True
            uc.emu_stop()

    emu.hook_add(UC_HOOK_CODE, on_code)
    entry_linear = ((load_segment + header["initial_cs"]) << 4) + header["initial_ip"]
    emu.emu_start(entry_linear, 0, count=20_000_000)
    if not stopped:
        cs = emu.reg_read(UC_X86_REG_CS)
        ip = emu.reg_read(UC_X86_REG_IP)
        raise SystemExit(f"loader did not reach original entry; stopped at {cs:04X}:{ip:04X}")

    dump_bytes = args.dump_bytes
    if dump_bytes is None:
        # EXEPACK stores the original stack immediately beyond the load image
        # for this executable family.  Retain one extra paragraph for analysis.
        dump_bytes = (original_ss + 1) * 16
    unpacked = bytes(emu.mem_read(load_segment << 4, dump_bytes))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(unpacked)

    print(f"load_segment={load_segment:04X}")
    print(f"original_entry={target_cs:04X}:{target_ip:04X}")
    print(f"original_stack={(load_segment + original_ss) & 0xFFFF:04X}:{original_sp:04X}")
    print(f"dump_bytes={len(unpacked)}")


if __name__ == "__main__":
    main()
