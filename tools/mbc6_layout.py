"""Shared layout constants for the MBC6 8 KiB bank-signature scheme.

Imported by both tools/gen_bank_data.py (which emits src/bank_data.asm)
and tools/verify_rom.py (which checks the final linked .gb), so the two
sides of the contract cannot silently drift apart.

Physical layout: RGBDS links ROMX banks as contiguous 16 KiB chunks
starting at file offset N*0x4000 (bank 0 is the fixed ROM at file
offset 0). Each RGBDS bank N in 1..RGBDS_BANK_COUNT-1 holds two MBC6
8 KiB physical banks: 2*N and 2*N+1. Bank 0 of the fixed ROM holds
physical banks 0 and 1 (only reachable there and, via the switchable
windows, through their own bank number).
"""

ROM_SIZE = 1024 * 1024
RGBDS_BANK_SIZE = 0x4000
MBC6_BANK_SIZE = 0x2000
RGBDS_BANK_COUNT = ROM_SIZE // RGBDS_BANK_SIZE  # 64
PHYSICAL_BANK_COUNT = ROM_SIZE // MBC6_BANK_SIZE  # 128

# Offset of the signature within its 8 KiB physical bank.
SIG_LOCAL_OFFSET = 0x1FF0
SIG_SIZE = 16

MAGIC = b"M6BK"


def signature_bytes(physical_bank: int) -> bytes:
    """Build the deterministic 16-byte signature for one physical 8 KiB bank."""
    if not 0 <= physical_bank < PHYSICAL_BANK_COUNT:
        raise ValueError(f"physical_bank out of range: {physical_bank}")

    rgbds_bank = physical_bank // 2
    subbank = physical_bank % 2

    body = bytearray()
    body += MAGIC                                   # +0..+3
    body.append(physical_bank & 0xFF)                # +4
    body.append((~physical_bank) & 0xFF)             # +5
    body.append(0xA5)                                # +6
    body.append(0x5A)                                # +7
    body.append((physical_bank * 3 + 7) & 0xFF)       # +8
    body.append((physical_bank ^ 0xFF) & 0xFF)        # +9
    body.append(rgbds_bank & 0xFF)                    # +10
    body.append(subbank & 0xFF)                       # +11

    checksum = sum(body) & 0xFF                      # +12
    body.append(checksum)
    body += bytes(3)                                  # +13..+15 reserved

    assert len(body) == SIG_SIZE
    return bytes(body)


def file_offset_for_bank(physical_bank: int) -> int:
    """Absolute byte offset of physical_bank's signature within the .gb file."""
    rgbds_bank = physical_bank // 2
    subbank = physical_bank % 2
    return rgbds_bank * RGBDS_BANK_SIZE + subbank * MBC6_BANK_SIZE + SIG_LOCAL_OFFSET
