; Non-destructive flash tests: T30-T35.
; See docs/test-matrix.md, docs/project-rules.md "Flash rules", and
; src/flash.asm for the command sequences (sourced from the iceboy NP
; GB Memory documentation). These tests never trigger a persistent
; erase/program/protect/unprotect operation. T35 briefly enters program/status
; mode but aborts before loading buffer data; see src/tests_flash_destructive.asm
; for the compile-time-gated suite that can trigger persistent operations.

INCLUDE "hardware.inc"
INCLUDE "mbc6.inc"
INCLUDE "tests.inc"

SECTION "T34 WRAM", WRAM0
wHiddenRegionChecksum:: db

SECTION "T35 WRAM", WRAM0
wSector0ProtectionStatus:: db

SECTION "TD9 WRAM", WRAM0
wTD9HiddenAChecksum:: db
wTD9HiddenBChecksum:: db

SECTION "TD10-TD12 Fixture WRAM", WRAM0
wTD10IDABManufacturer:: db
wTD10IDABDevice::       db
wTD10IDBAManufacturer:: db
wTD10IDBADevice::       db
wTD11ProgramBusyA::     db
wTD11ProgramBusyB::     db
wTD11ProgramReadyA::   db
wTD11ProgramReadyB::   db
wTD11ChipBusyA::       db
wTD11ChipBusyB::       db
wTD11ChipReadyA::      db
wTD11ChipReadyB::      db
wTD12Edge0::            db
wTD12Edge7F::           db
wTD12EdgeLast0::        db
wTD12EdgeLast127::      db

SECTION "Flash Tests", ROM0

; --- Test_T30 --- ROM/Flash source-latch isolation and bank retention.
; Never asserts any flash contents. Toggle one source latch at a time and
; check the opposite window's known ROM signature before touching its source.
; The 16-byte signature detects cross-coupling unless flash happens to contain
; the exact same signature at that mapped location.
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

    ; A -> Flash must leave B's source and bank untouched.
    call MBC6_SelectFlashA
    ld a, 20
    ld de, WIN_B_SIG
    call CheckBankSignatureAt
    jr c, .fail

    ; Restore A and verify its bank number was retained.
    call MBC6_SelectROMA
    ld a, 10
    ld de, WIN_A_SIG
    call CheckBankSignatureAt
    jr c, .fail

    ; B -> Flash must leave A's source and bank untouched.
    call MBC6_SelectFlashB
    ld a, 10
    ld de, WIN_A_SIG
    call CheckBankSignatureAt
    jr c, .fail

    ; Restore B and verify its bank number was retained.
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
    call Flash_EnterIDModeViaBankB
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
    ; Expect a non-ID value here so CheckByteAt records the persistent
    ; $81 as a T33 failure instead of treating equality as a pass.
    xor a
    ld de, MBC6_ROM_WIN_A + 1
    ld c, 0
    call CheckByteAt
    jr c, .fail
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

; --- Test_T35 --- Sector-0 protection status observation (INFO).
; Iceboy documents entering program/status mode under WP, sampling bit 1,
; and resetting before any buffer data/trigger. This is observational: no
; hardware protection expectation is assumed for every cartridge.
EXPORT Test_T35
Test_T35:
    call Flash_EnterSector0Status
    ld a, [MBC6_ROM_WIN_A]
    ld [wSector0ProtectionStatus], a
    call Flash_Reset
    ld a, T_35
    ld d, RESULT_INFO
    call RecordResult
    ret
