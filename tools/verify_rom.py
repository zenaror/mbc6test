#!/usr/bin/env python3
"""Static verification for the built MBC6 test ROM.

Run by `make verify`. Exits non-zero if any invariant is broken. This
checks the final linked/fixed .gb file, not source macros — per
CLAUDE.md "Host-side verification": "Prefer verifying the final
linked/fixed ROM rather than trusting source macros."
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mbc6_layout import PHYSICAL_BANK_COUNT, ROM_SIZE, file_offset_for_bank, signature_bytes

HDR_CGB_FLAG   = 0x0143
HDR_CART_TYPE  = 0x0147
HDR_ROM_SIZE   = 0x0148
HDR_RAM_SIZE   = 0x0149
HDR_CHECKSUM   = 0x014D
HDR_GLOBAL_CHK = 0x014E

EXPECTED_CGB_FLAG  = 0xC0
EXPECTED_CART_TYPE = 0x20
EXPECTED_ROM_SIZE  = 0x05
EXPECTED_RAM_SIZE  = 0x03


class VerifyError(Exception):
    pass


def check_size(data: bytes) -> None:
    if len(data) != ROM_SIZE:
        raise VerifyError(f"ROM size is {len(data)} bytes, expected exactly {ROM_SIZE}")


def check_header_bytes(data: bytes) -> None:
    checks = [
        ("CGB flag ($0143)", HDR_CGB_FLAG, EXPECTED_CGB_FLAG),
        ("cartridge type ($0147)", HDR_CART_TYPE, EXPECTED_CART_TYPE),
        ("ROM size ($0148)", HDR_ROM_SIZE, EXPECTED_ROM_SIZE),
        ("RAM size ($0149)", HDR_RAM_SIZE, EXPECTED_RAM_SIZE),
    ]
    for name, offset, expected in checks:
        actual = data[offset]
        if actual != expected:
            raise VerifyError(f"{name} = ${actual:02X}, expected ${expected:02X}")


def check_header_checksum(data: bytes) -> None:
    # Pan Docs: sum of bytes $0134-$014C, complemented, stored at $014D.
    total = 0
    for b in data[0x0134:0x014D]:
        total = (total - b - 1) & 0xFF
    actual = data[HDR_CHECKSUM]
    if actual != total:
        raise VerifyError(f"header checksum = ${actual:02X}, expected ${total:02X}")


def check_global_checksum(data: bytes) -> None:
    # Pan Docs: sum of all bytes except the two global-checksum bytes
    # themselves, big-endian, stored at $014E-$014F.
    total = sum(data[:HDR_GLOBAL_CHK]) + sum(data[HDR_GLOBAL_CHK + 2:])
    total &= 0xFFFF
    actual = (data[HDR_GLOBAL_CHK] << 8) | data[HDR_GLOBAL_CHK + 1]
    if actual != total:
        raise VerifyError(f"global checksum = ${actual:04X}, expected ${total:04X}")


def check_bank_signatures(data: bytes) -> None:
    seen = {}
    for bank in range(PHYSICAL_BANK_COUNT):
        offset = file_offset_for_bank(bank)
        expected = signature_bytes(bank)
        actual = data[offset:offset + len(expected)]
        if actual != expected:
            raise VerifyError(
                f"bank {bank} signature mismatch at file offset ${offset:06X}: "
                f"expected {expected.hex(' ')}, got {actual.hex(' ')}"
            )
        if actual in seen:
            raise VerifyError(
                f"bank {bank} signature is a duplicate of bank {seen[actual]} "
                f"(non-unique signatures)"
            )
        seen[actual] = bank


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify_rom.py <path-to-.gb>", file=sys.stderr)
        return 2

    rom_path = Path(sys.argv[1])
    if not rom_path.is_file():
        print(f"FAIL: ROM not found: {rom_path}", file=sys.stderr)
        return 1

    data = rom_path.read_bytes()

    checks = [
        ("image size", check_size),
        ("header bytes", check_header_bytes),
        ("header checksum", check_header_checksum),
        ("global checksum", check_global_checksum),
        ("bank signatures (128 physical 8 KiB banks)", check_bank_signatures),
    ]

    failures = 0
    for name, fn in checks:
        try:
            fn(data)
        except VerifyError as e:
            print(f"FAIL [{name}]: {e}", file=sys.stderr)
            failures += 1
        else:
            print(f"OK   [{name}]")

    if failures:
        print(f"\n{failures} check(s) failed.", file=sys.stderr)
        return 1

    print("\nAll static checks passed.")
    print("NOTE: this only validates static ROM invariants (header, size,")
    print("bank signatures). It does NOT prove runtime MBC6 behavior —")
    print("that still needs to be checked in BGB/another emulator or on")
    print("real hardware.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
