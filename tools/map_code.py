#!/usr/bin/env python3
"""Recursively map reachable 16-bit code in an unpacked DOS load image."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from capstone import CS_ARCH_X86, CS_GRP_CALL, CS_GRP_JUMP, CS_MODE_16, Cs
from capstone.x86_const import X86_OP_IMM


TERMINATORS = {"ret", "retf", "iret", "hlt", "int3"}
UNCONDITIONAL_JUMPS = {"jmp", "ljmp"}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("--entry", type=lambda value: int(value, 0), default=0xEA7E)
    parser.add_argument("--listing", type=Path)
    args = parser.parse_args()

    data = args.image.read_bytes()
    md = Cs(CS_ARCH_X86, CS_MODE_16)
    md.detail = True

    pending = deque([args.entry])
    queued = {args.entry}
    decoded: dict[int, object] = {}
    block_starts: set[int] = {args.entry}

    while pending:
        pc = pending.popleft()
        while 0 <= pc < len(data) and pc not in decoded:
            result = next(md.disasm(data[pc : pc + 16], pc, count=1), None)
            if result is None:
                break
            decoded[pc] = result
            next_pc = pc + result.size

            immediate_target = None
            if result.operands and result.operands[0].type == X86_OP_IMM:
                immediate_target = result.operands[0].imm & 0xFFFF

            if result.group(CS_GRP_CALL) and immediate_target is not None:
                if immediate_target < len(data) and immediate_target not in queued:
                    pending.append(immediate_target)
                    queued.add(immediate_target)
                    block_starts.add(immediate_target)

            if result.group(CS_GRP_JUMP) and immediate_target is not None:
                if immediate_target < len(data) and immediate_target not in queued:
                    pending.append(immediate_target)
                    queued.add(immediate_target)
                    block_starts.add(immediate_target)
                if result.mnemonic in UNCONDITIONAL_JUMPS:
                    break

            if result.mnemonic in TERMINATORS:
                break
            pc = next_pc

    ordered = [decoded[key] for key in sorted(decoded)]
    listing = "\n".join(
        f"{ins.address:04X}: {ins.bytes.hex(' '):<24} {ins.mnemonic:<7} {ins.op_str}"
        for ins in ordered
    ) + "\n"
    if args.listing:
        args.listing.parent.mkdir(parents=True, exist_ok=True)
        args.listing.write_text(listing)

    io = [
        ins
        for ins in ordered
        if ins.mnemonic in {"in", "insb", "insw", "out", "outsb", "outsw"}
    ]
    interrupts = [ins for ins in ordered if ins.mnemonic in {"int", "int1", "int3"}]
    indirect_calls = [
        ins
        for ins in ordered
        if ins.group(CS_GRP_CALL)
        and (not ins.operands or ins.operands[0].type != X86_OP_IMM)
    ]
    print(f"instructions={len(ordered)}")
    print(f"code_bytes={sum(ins.size for ins in ordered)}")
    print(f"blocks={len(block_starts)}")
    print("I/O instructions:")
    for ins in io:
        print(f"  {ins.address:04X}: {ins.mnemonic} {ins.op_str}")
    print("Interrupt instructions:")
    for ins in interrupts:
        print(f"  {ins.address:04X}: {ins.mnemonic} {ins.op_str}")
    print("Indirect calls:")
    for ins in indirect_calls:
        print(f"  {ins.address:04X}: {ins.mnemonic} {ins.op_str}")


if __name__ == "__main__":
    main()
