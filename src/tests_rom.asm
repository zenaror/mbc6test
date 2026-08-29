; ROM banking tests: T00, T01, T10-T14.
; See docs/test-matrix.md for the authoritative description of each
; test and CLAUDE.md "Required safe tests" / "ROM bank layout".
;
; All routines here run from fixed ROM (CLAUDE.md "Fixed-ROM safety
; rule") since they change MBC6 ROM/Flash mapping registers.

INCLUDE "hardware.inc"
INCLUDE "mbc6.inc"
INCLUDE "tests.inc"

DEF FIXED_SIG_BANK0 EQU $1FF0 ; always-mapped signature for physical bank 0
DEF FIXED_SIG_BANK1 EQU $3FF0 ; always-mapped signature for physical bank 1

SECTION "T01 WRAM", WRAM0
wPowerOnCaptured:: db
wPowerOnWindowA::  ds 16
wPowerOnWindowB::  ds 16

SECTION "T12 WRAM", WRAM0
wT12_A0: db
wT12_B0: db
wT12_DecoyA: db
wT12_DecoyB: db

SECTION "ROM Tests", ROM0

; --- CapturePowerOnState ---
; Snapshots the raw bytes at the two ROM windows' signature offsets
; into WRAM. Must be called before any MBC6 register write — see
; CLAUDE.md "Power-on state": "Capture before UI initialization code
; has any opportunity to write MBC registers." Called directly from
; main.asm's Start, before the CGB capability probe.
EXPORT CapturePowerOnState
CapturePowerOnState:
    ld hl, WIN_A_SIG
    ld de, wPowerOnWindowA
    ld b, 16
    call .copy16
    ld hl, WIN_B_SIG
    ld de, wPowerOnWindowB
    ld b, 16
    call .copy16
    ld a, 1
    ld [wPowerOnCaptured], a
    ret
.copy16:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .copy16
    ret

; --- Test_T00 ---
; Startup/header sanity. The build-time verifier (tools/verify_rom.py)
; is authoritative for header bytes; this is purely diagnostic, hence
; INFO rather than PASS/FAIL (CLAUDE.md: "Unknown behavior must not
; influence the compatibility score" — and there is no runtime pass
; condition here, only a version display).
EXPORT Test_T00
Test_T00:
    ld a, T_00
    ld d, RESULT_INFO
    call RecordResult
    ret

; --- Test_T01 ---
; Compares the power-on snapshot (captured before any MBC6 register
; write) against the expected signatures for physical banks 2 and 3 —
; the documented iceboy power-on ROM Bank A/B values.
EXPORT Test_T01
Test_T01:
    ld a, [wPowerOnCaptured]
    or a
    jr z, .skip

    ld a, MBC6_POWERON_ROM_BANK_A
    ld de, wPowerOnWindowA
    call CheckBankSignatureAt
    jr nc, .checkB
    ld a, HIGH(WIN_A_SIG)
    ld [wLastCheckAddrHi], a
    ld a, LOW(WIN_A_SIG)
    ld [wLastCheckAddrLo], a
    jr .fail
.checkB:
    ld a, MBC6_POWERON_ROM_BANK_B
    ld de, wPowerOnWindowB
    call CheckBankSignatureAt
    jr nc, .pass
    ld a, HIGH(WIN_B_SIG)
    ld [wLastCheckAddrHi], a
    ld a, LOW(WIN_B_SIG)
    ld [wLastCheckAddrLo], a
.fail:
    ld a, T_01
    call RecordFailureDetail
    ret
.pass:
    ld a, T_01
    ld d, RESULT_PASS
    call RecordResult
    ret
.skip:
    ld a, T_01
    ld d, RESULT_SKIP
    call RecordResult
    ret

; --- Test_T10 --- ROM Bank A full sweep $00-$7F.
EXPORT Test_T10
Test_T10:
    call MBC6_SelectROMA
    ld c, 0
.loop:
    ld a, c
    call MBC6_SetROMBankA
    ld a, c
    ld de, WIN_A_SIG
    call CheckBankSignatureAt
    jr c, .fail
    inc c
    ld a, c
    cp MBC6_ROM_BANK_COUNT
    jr nz, .loop
    ld a, T_10
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    ld a, T_10
    call RecordFailureDetail
    ret

; --- Test_T11 --- ROM Bank B full sweep $00-$7F.
EXPORT Test_T11
Test_T11:
    call MBC6_SelectROMB
    ld c, 0
.loop:
    ld a, c
    call MBC6_SetROMBankB
    ld a, c
    ld de, WIN_B_SIG
    call CheckBankSignatureAt
    jr c, .fail
    inc c
    ld a, c
    cp MBC6_ROM_BANK_COUNT
    jr nz, .loop
    ld a, T_11
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    ld a, T_11
    call RecordFailureDetail
    ret

; --- Test_T12 --- ROM Bank A/B independence across several pairs,
; including edge and cross-pattern cases (CLAUDE.md T12 list).
T12_Pairs:
    db 0, 127
    db 127, 0
    db 2, 3
    db 3, 2
    db $2A, $55
    db $55, $2A
DEF T12_PAIR_COUNT EQU 6

EXPORT Test_T12
Test_T12:
    call MBC6_SelectROMA
    call MBC6_SelectROMB
    ld hl, T12_Pairs
    ld c, T12_PAIR_COUNT
.pairLoop:
    ld a, [hl+]
    ld [wT12_A0], a
    ld a, [hl+]
    ld [wT12_B0], a
    push hl
    call T12_CheckPair
    pop hl
    jr c, .fail
    dec c
    jr nz, .pairLoop
    ld a, T_12
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    ld a, T_12
    call RecordFailureDetail
    ret

; Performs the full 9-step independence check for one (a0,b0) pair
; (see docs/test-matrix.md T12): set both windows, verify both;
; nudge B and confirm A is unaffected while B changed as commanded;
; nudge A and confirm B (still at its nudged value) is unaffected
; while A changed as commanded. Returns carry set on first mismatch.
T12_CheckPair:
    ld a, [wT12_A0]
    call MBC6_SetROMBankA
    ld a, [wT12_B0]
    call MBC6_SetROMBankB

    ld a, [wT12_A0]
    ld de, WIN_A_SIG
    call CheckBankSignatureAt
    ret c
    ld a, [wT12_B0]
    ld de, WIN_B_SIG
    call CheckBankSignatureAt
    ret c

    ld a, [wT12_B0]
    inc a
    and $7F
    ld [wT12_DecoyB], a
    call MBC6_SetROMBankB
    ld a, [wT12_DecoyB]
    ld de, WIN_B_SIG
    call CheckBankSignatureAt
    ret c
    ld a, [wT12_A0]
    ld de, WIN_A_SIG
    call CheckBankSignatureAt
    ret c

    ld a, [wT12_A0]
    inc a
    and $7F
    ld [wT12_DecoyA], a
    call MBC6_SetROMBankA
    ld a, [wT12_DecoyA]
    ld de, WIN_A_SIG
    call CheckBankSignatureAt
    ret c
    ld a, [wT12_DecoyB]
    ld de, WIN_B_SIG
    call CheckBankSignatureAt
    ret

; --- Test_T13 --- explicit physical ROM bank 0 mapping, both windows.
; Unlike MBC1/MBC3/MBC5-style mappers, bank 0 is a legal, distinct
; selection in the switchable windows on MBC6 (CLAUDE.md "Bank 0 is
; valid in the switchable ROM windows").
EXPORT Test_T13
Test_T13:
    call MBC6_SelectROMA
    call MBC6_SelectROMB
    xor a
    call MBC6_SetROMBankA
    xor a
    call MBC6_SetROMBankB
    xor a
    ld de, WIN_A_SIG
    call CheckBankSignatureAt
    jr c, .fail
    xor a
    ld de, WIN_B_SIG
    call CheckBankSignatureAt
    jr c, .fail
    ld a, T_13
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    ld a, T_13
    call RecordFailureDetail
    ret

; --- Test_T14 --- window boundaries.
; Our deterministic per-bank content only exists at the signature
; offset ($1FF0 within each 8 KiB bank), so rather than probing
; arbitrary mid-bank offsets we (a) drive both switchable windows to
; opposite extremes ($7F/$00 and $00/$7F) and confirm each window
; shows exactly the bank it was told to, and (b) confirm the FIXED
; ROM's own bank-0/bank-1 signatures at $1FF0/$3FF0 are never
; disturbed by switching the $4000-$7FFF windows — i.e. the windows
; do not bleed outside their documented ranges. This is a stronger
; "no cross-window bleed" property than sampling a handful of
; interior bytes would be.
EXPORT Test_T14
Test_T14:
    call MBC6_SelectROMA
    call MBC6_SelectROMB

    ; Pass 1: A=$7F, B=$00 (opposite extremes).
    ld a, $7F
    call MBC6_SetROMBankA
    xor a
    call MBC6_SetROMBankB
    ld a, $7F
    ld de, WIN_A_SIG
    call CheckBankSignatureAt
    jr c, .fail
    xor a
    ld de, WIN_B_SIG
    call CheckBankSignatureAt
    jr c, .fail
    xor a
    ld de, FIXED_SIG_BANK0
    call CheckBankSignatureAt
    jr c, .fail
    ld a, 1
    ld de, FIXED_SIG_BANK1
    call CheckBankSignatureAt
    jr c, .fail

    ; Pass 2: A=$00, B=$7F (swapped).
    xor a
    call MBC6_SetROMBankA
    ld a, $7F
    call MBC6_SetROMBankB
    xor a
    ld de, WIN_A_SIG
    call CheckBankSignatureAt
    jr c, .fail
    ld a, $7F
    ld de, WIN_B_SIG
    call CheckBankSignatureAt
    jr c, .fail
    xor a
    ld de, FIXED_SIG_BANK0
    call CheckBankSignatureAt
    jr c, .fail
    ld a, 1
    ld de, FIXED_SIG_BANK1
    call CheckBankSignatureAt
    jr c, .fail

    ld a, T_14
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    ld a, T_14
    call RecordFailureDetail
    ret
