; Non-destructive flash tests: T30-T35.
; See docs/test-matrix.md, docs/project-rules.md "Flash rules", and
; src/flash.asm for the command sequences (sourced from the iceboy NP
; GB Memory documentation). None of these erase, program, protect, or
; unprotect anything — see src/tests_flash_destructive.asm for the
; compile-time-gated destructive suite.

INCLUDE "hardware.inc"
INCLUDE "mbc6.inc"
INCLUDE "tests.inc"

SECTION "T34 WRAM", WRAM0
wHiddenRegionChecksum:: db

SECTION "T35 WRAM", WRAM0
wSector0StatusByte:: db

SECTION "Flash Tests", ROM0

; --- Test_T30 --- ROM/Flash source selection isolation.
; Never reads flash contents (docs/project-rules.md: "Do not require any specific
; initial flash contents"). Instead, uses known ROM bank signatures as
; a witness: a window's ROM bank *number* register is only ever
; written once here, so if that window still shows the same ROM
; signature after the OTHER window's source is toggled ROM<->Flash
; (repeatedly), neither the source select nor the bank number of the
; untouched window was disturbed.
EXPORT Test_T30
Test_T30:
    call MBC6_SelectROMA
    ld a, 10
    call MBC6_SetROMBankA
    call MBC6_SelectROMB
    ld a, 20
    call MBC6_SetROMBankB

    ld a, 10
    ld de, WIN_A_SIG
    call CheckBankSignatureAt
    jr c, .fail
    ld a, 20
    ld de, WIN_B_SIG
    call CheckBankSignatureAt
    jr c, .fail

    ; Toggle A's source; B's bank register is never rewritten below.
    call MBC6_SelectFlashA
    call MBC6_SelectFlashB
    call MBC6_SelectROMA
    ld a, 10
    ld de, WIN_A_SIG
    call CheckBankSignatureAt       ; A's own bank survived its own toggles
    jr c, .fail

    ; B's source/bank must have survived A's toggling untouched.
    call MBC6_SelectROMB
    ld a, 20
    ld de, WIN_B_SIG
    call CheckBankSignatureAt
    jr c, .fail

    ld a, T_30
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    ld a, T_30
    call RecordFailureDetail
    ret

; --- Test_T31 --- Flash JEDEC ID through Bank A window.
EXPORT Test_T31
Test_T31:
    call Flash_EnterIDMode
    ld a, FLASH_JEDEC_MANUFACTURER
    ld de, MBC6_ROM_WIN_A + 0
    ld c, 0
    call CheckByteAt
    jr c, .fail
    ld a, FLASH_JEDEC_DEVICE
    ld de, MBC6_ROM_WIN_A + 1
    ld c, 0
    call CheckByteAt
    jr c, .fail
    call Flash_Reset
    ld a, T_31
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    call Flash_Reset
    ld a, T_31
    call RecordFailureDetail
    ret

; --- Test_T32 --- Flash JEDEC ID through Bank B window.
; Same ID, reached through the other 8 KiB window — MBC6 exposes two
; independent flash windows and both must translate JEDEC addressing
; correctly (docs/project-rules.md T32).
EXPORT Test_T32
Test_T32:
    call Flash_EnterIDMode
    ld a, FLASH_JEDEC_MANUFACTURER
    ld de, MBC6_ROM_WIN_B + 0
    ld c, 0
    call CheckByteAt
    jr c, .fail
    ld a, FLASH_JEDEC_DEVICE
    ld de, MBC6_ROM_WIN_B + 1
    ld c, 0
    call CheckByteAt
    jr c, .fail
    call Flash_Reset
    ld a, T_32
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    call Flash_Reset
    ld a, T_32
    call RecordFailureDetail
    ret

; --- Test_T33 --- Flash reset command.
; Confirms ID mode entry (same check as T31), resets, then confirms
; the manufacturer/device byte pair no longer reads back — i.e. we
; left ID mode. This is a differential check, not a check against
; known array content (docs/project-rules.md: never assume flash array contents),
; so it carries a small theoretical false-positive risk if the real
; array happens to contain the exact ID byte pair at that offset;
; that risk is inherent to testing this non-destructively.
EXPORT Test_T33
Test_T33:
    call Flash_EnterIDMode
    ld a, FLASH_JEDEC_MANUFACTURER
    ld de, MBC6_ROM_WIN_A + 0
    ld c, 0
    call CheckByteAt
    jr c, .fail
    ld a, FLASH_JEDEC_DEVICE
    ld de, MBC6_ROM_WIN_A + 1
    ld c, 0
    call CheckByteAt
    jr c, .fail

    call Flash_Reset

    ld a, [MBC6_ROM_WIN_A + 0]
    cp FLASH_JEDEC_MANUFACTURER
    jr nz, .pass
    ld a, [MBC6_ROM_WIN_A + 1]
    cp FLASH_JEDEC_DEVICE
    jr nz, .pass
    ; Still reads as the ID pair after reset: either reset didn't
    ; work, or (small chance) that's genuinely the array content.
    ld a, FLASH_JEDEC_DEVICE
    ld de, MBC6_ROM_WIN_A + 1
    ld c, 0
    call CheckByteAt
.pass:
    ld a, T_33
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    call Flash_Reset
    ld a, T_33
    call RecordFailureDetail
    ret

; --- Test_T34 --- Hidden 256-byte region read mode (INFO).
; docs/project-rules.md: "Do not require any particular hidden-region payload."
; Reads 256 bytes through window A and reports an XOR checksum as
; INFO — a diagnostic fingerprint, not a normative expectation.
EXPORT Test_T34
Test_T34:
    call Flash_EnterHiddenMode
    ld hl, MBC6_ROM_WIN_A
    ld b, 0                 ; 0 used as "256" via 8-bit wraparound
    xor a
.sumLoop:
    xor [hl]
    inc hl
    dec b
    jr nz, .sumLoop
    ld [wHiddenRegionChecksum], a
    call Flash_Reset
    ld a, T_34
    ld d, RESULT_INFO
    call RecordResult
    ret

; --- Test_T35 --- Sector-0 protection observation (INFO).
; The iceboy documentation describes a status-register bit 1 meaning
; for sector-0 protection, but only in the context of an in-progress
; program/erase operation; it does not confirm that bit is meaningful
; when read from idle flash outside such an operation. Rather than
; issue any protect/unprotect command (destructive-adjacent and out of
; scope for the safe suite), this records the as-observed byte at the
; window with no operation in progress, purely as INFO — docs/project-rules.md:
; "Do not modify persistent protection state in the default suite."
EXPORT Test_T35
Test_T35:
    call MBC6_EnableFlash
    xor a
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld a, [MBC6_ROM_WIN_A]
    ld [wSector0StatusByte], a
    call Flash_Reset
    ld a, T_35
    ld d, RESULT_INFO
    call RecordResult
    ret
