; MBC6 mapper register helpers.
;
; CLAUDE.md "Fixed-ROM safety rule": any routine that writes MBC6
; ROM/Flash mapping registers must execute from $0000-$3FFF. Every
; routine in this file lives in ROM0 for that reason — never move any
; of these into a ROMX bank.

INCLUDE "hardware.inc"
INCLUDE "mbc6.inc"

SECTION "MBC6 Helpers", ROM0

; --- MBC6_SetROMBankA / B ---
; Select the 8 KiB ROM/Flash bank number shown in the given window.
; Input: a = bank number (0-127). Clobbers: none besides a's use.
EXPORT MBC6_SetROMBankA
MBC6_SetROMBankA:
    ld [MBC6_REG_ROM_BANK_A], a
    ret

EXPORT MBC6_SetROMBankB
MBC6_SetROMBankB:
    ld [MBC6_REG_ROM_BANK_B], a
    ret

; --- MBC6_SelectROMA / B, MBC6_SelectFlashA / B ---
; Choose whether a window's bank number indexes into ROM or flash.
EXPORT MBC6_SelectROMA
MBC6_SelectROMA:
    ld a, MBC6_SRC_ROM
    ld [MBC6_REG_ROM_SRC_A], a
    ret

EXPORT MBC6_SelectROMB
MBC6_SelectROMB:
    ld a, MBC6_SRC_ROM
    ld [MBC6_REG_ROM_SRC_B], a
    ret

EXPORT MBC6_SelectFlashA
MBC6_SelectFlashA:
    ld a, MBC6_SRC_FLASH
    ld [MBC6_REG_ROM_SRC_A], a
    ret

EXPORT MBC6_SelectFlashB
MBC6_SelectFlashB:
    ld a, MBC6_SRC_FLASH
    ld [MBC6_REG_ROM_SRC_B], a
    ret

; --- MBC6_SetRAMBankA / B ---
; Input: a = 4 KiB SRAM bank number (0-7).
EXPORT MBC6_SetRAMBankA
MBC6_SetRAMBankA:
    ld [MBC6_REG_SRAM_BANK_A], a
    ret

EXPORT MBC6_SetRAMBankB
MBC6_SetRAMBankB:
    ld [MBC6_REG_SRAM_BANK_B], a
    ret

; --- MBC6_EnableRAM / DisableRAM ---
EXPORT MBC6_EnableRAM
MBC6_EnableRAM:
    ld a, MBC6_SRAM_ENABLE_VALUE
    ld [MBC6_REG_SRAM_ENABLE], a
    ret

EXPORT MBC6_DisableRAM
MBC6_DisableRAM:
    ld a, MBC6_SRAM_DISABLE_VALUE
    ld [MBC6_REG_SRAM_ENABLE], a
    ret

; --- MBC6_EnableFlash / DisableFlash ---
; Flash Enable ($0C00-$0FFF). Distinct from Flash Write Enable/WP
; ($1000) implemented in flash.asm — CLAUDE.md warns not to conflate
; the two: this bit exposes flash for reading/ID/commands, WP protects
; sector 0 and the hidden region specifically, not a generic global
; write-enable.
EXPORT MBC6_EnableFlash
MBC6_EnableFlash:
    ld a, MBC6_FLASH_ENABLE_VALUE
    ld [MBC6_REG_FLASH_ENABLE], a
    ret

EXPORT MBC6_DisableFlash
MBC6_DisableFlash:
    ld a, MBC6_FLASH_DISABLE_VALUE
    ld [MBC6_REG_FLASH_ENABLE], a
    ret
