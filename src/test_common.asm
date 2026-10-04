; Shared test-framework primitives: bank signature verification,
; result recording, and first-failure capture.
;
; This is not in the file list suggested by docs/project-rules.md, but factoring
; it out keeps the actual test bodies (tests_rom.asm etc.) short and
; auditable instead of duplicating this bookkeeping in every test.
; Everything here runs from fixed ROM, since callers use it while
; MBC6 registers are being changed (docs/project-rules.md "Fixed-ROM safety rule"
; — "Keep core mapper helpers, ... assertions, ... in fixed ROM").

INCLUDE "hardware.inc"
INCLUDE "mbc6.inc"
INCLUDE "tests.inc"

SECTION "Test Common WRAM", WRAM0
; Per-test compact status, one byte each, RESULT_* — drives the
; summary counts and the category/detail UI.
wTestStatus:: ds NUM_TESTS

wSummaryPass:: db
wSummaryFail:: db
wSummarySkip:: db
wSummaryInfo:: db

; Scratch used by CheckBankSignatureAt for its most recent comparison.
wSigBankNum:  db
wSigScratch:  ds 16
wLastCheckBank::     db
wLastCheckAddrHi::   db
wLastCheckAddrLo::   db
wLastCheckExpected:: db
wLastCheckActual::   db

; Permanent first-failure record (docs/project-rules.md: "Prefer a precise
; first-failure report over a generic 'MBC6 FAIL'"). Only the first
; FAIL across the whole run populates this.
wFailureRecorded:: db
wFailTestID::   db
wFailBank::     db
wFailAddrHi::   db
wFailAddrLo::   db
wFailExpected:: db
wFailActual::   db

; Scratch for WriteResultBlock's failed-test bitset (24 bits, covers
; test IDs 0-23 — see docs/result-format.md).
wFailedBitset: ds 3

SECTION "Test Common", ROM0

; --- ResetTestState ---
; Clears all per-test status, summary counters, and the first-failure
; record. Call once before running any test batch.
EXPORT ResetTestState
ResetTestState:
    ld a, RESULT_NOT_RUN
    ld hl, wTestStatus
    ld b, NUM_TESTS
.clearStatus:
    ld [hl+], a
    dec b
    jr nz, .clearStatus
    xor a
    ld [wSummaryPass], a
    ld [wSummaryFail], a
    ld [wSummarySkip], a
    ld [wSummaryInfo], a
    ld [wFailureRecorded], a
    ret

; --- RecordResult ---
; Input: a = test id, d = result status (RESULT_*).
; Stores the status and bumps the matching summary counter.
EXPORT RecordResult
RecordResult:
    push af
    push bc
    push de
    push hl
    ld hl, wTestStatus
    ld c, a
    ld b, 0
    add hl, bc
    ld [hl], d
    ld a, d
    cp RESULT_PASS
    jr nz, .notPass
    ld hl, wSummaryPass
    inc [hl]
    jr .done
.notPass:
    cp RESULT_FAIL
    jr nz, .notFail
    ld hl, wSummaryFail
    inc [hl]
    jr .done
.notFail:
    cp RESULT_SKIP
    jr nz, .notSkip
    ld hl, wSummarySkip
    inc [hl]
    jr .done
.notSkip:
    ld hl, wSummaryInfo
    inc [hl]
.done:
    pop hl
    pop de
    pop bc
    pop af
    ret

; --- RecordFailureDetail ---
; Input: a = test id.
; Records RESULT_FAIL for this test, and — only if no failure has been
; recorded yet this run — copies wLastCheck* (populated by the most
; recent CheckBankSignatureAt mismatch) into the permanent
; wFail*/first-failure record.
EXPORT RecordFailureDetail
RecordFailureDetail:
    push af
    ld hl, wFailureRecorded
    ld a, [hl]
    or a
    jr nz, .alreadyRecorded
    ld [hl], 1
    pop af
    push af
    ld [wFailTestID], a
    ld a, [wLastCheckBank]
    ld [wFailBank], a
    ld a, [wLastCheckAddrHi]
    ld [wFailAddrHi], a
    ld a, [wLastCheckAddrLo]
    ld [wFailAddrLo], a
    ld a, [wLastCheckExpected]
    ld [wFailExpected], a
    ld a, [wLastCheckActual]
    ld [wFailActual], a
.alreadyRecorded:
    pop af
    ld d, RESULT_FAIL
    call RecordResult
    ret

; --- ComputeExpectedSignature ---
; Input: a = physical 8 KiB bank number (0-127).
; Output: wSigScratch[0..15] filled with the expected 16-byte
; signature for that bank, using the exact same formula as
; tools/mbc6_layout.py signature_bytes() — keep the two in sync.
; Clobbers: a, b, c, hl.
EXPORT ComputeExpectedSignature
ComputeExpectedSignature:
    ld [wSigBankNum], a
    ld hl, wSigScratch
    ld a, $4D ; 'M'
    ld [hl+], a
    ld a, $36 ; '6'
    ld [hl+], a
    ld a, $42 ; 'B'
    ld [hl+], a
    ld a, $4B ; 'K'
    ld [hl+], a
    ld a, [wSigBankNum]
    ld [hl+], a             ; +4 bank
    cpl
    ld [hl+], a             ; +5 ~bank
    ld a, $A5
    ld [hl+], a             ; +6 sentinel
    ld a, $5A
    ld [hl+], a             ; +7 sentinel
    ld a, [wSigBankNum]
    ld b, a
    add a, a
    add a, b                ; a = bank*3 (mod 256)
    add a, 7                ; a = bank*3+7 (mod 256)
    ld [hl+], a             ; +8
    ld a, [wSigBankNum]
    xor $FF
    ld [hl+], a             ; +9 bank XOR $FF
    ld a, [wSigBankNum]
    srl a                   ; a = bank >> 1 (RGBDS bank index)
    ld [hl+], a             ; +10
    ld a, [wSigBankNum]
    and $01                 ; subbank (0 or 1)
    ld [hl+], a             ; +11
    ld hl, wSigScratch
    ld b, 12
    xor a
.sumLoop:
    add a, [hl]
    inc hl
    dec b
    jr nz, .sumLoop
    ld [hl+], a             ; +12 checksum
    xor a
    ld [hl+], a             ; +13
    ld [hl+], a             ; +14
    ld [hl+], a             ; +15
    ret

; --- CheckBankSignatureAt ---
; Input: a = physical bank number the window is expected to show,
;        de = CPU address of the window's 16-byte signature slot
;             (i.e. $5FF0 for window A, $7FF0 for window B).
; Output: carry clear if the 16 bytes at [de] match the expected
;         signature for bank a; carry set on the first mismatching
;         byte, with wLastCheckBank/AddrHi/AddrLo/Expected/Actual
;         populated for the caller to hand to RecordFailureDetail.
; Clobbers: a, b, hl (de is preserved up to the mismatch point).
EXPORT CheckBankSignatureAt
CheckBankSignatureAt:
    call ComputeExpectedSignature
    ld hl, wSigScratch
    ld b, 16
.cmpLoop:
    ld a, [de]
    cp [hl]
    jr nz, .mismatch
    inc hl
    inc de
    dec b
    jr nz, .cmpLoop
    xor a                   ; also clears carry: match
    ret
.mismatch:
    ld [wLastCheckActual], a
    ld a, [hl]
    ld [wLastCheckExpected], a
    ld a, [wSigBankNum]
    ld [wLastCheckBank], a
    ld a, d
    ld [wLastCheckAddrHi], a
    ld a, e
    ld [wLastCheckAddrLo], a
    scf
    ret

; --- CheckByteAt ---
; Single-byte counterpart to CheckBankSignatureAt, used by the SRAM
; tests (a bank signature is overkill for a 4 KiB SRAM bank's marker
; byte). Input: a = expected value, de = address to read, c = bank
; number to report in the diagnostic record on mismatch.
; Output: carry clear on match; carry set on mismatch, with
; wLastCheckBank/AddrHi/AddrLo/Expected/Actual populated.
; Clobbers: a. Preserves b, c, d, e, h, l.
EXPORT CheckByteAt
CheckByteAt:
    ld l, a
    ld a, [de]
    cp l
    jr z, .match
    ld [wLastCheckActual], a
    ld a, l
    ld [wLastCheckExpected], a
    ld a, c
    ld [wLastCheckBank], a
    ld a, d
    ld [wLastCheckAddrHi], a
    ld a, e
    ld [wLastCheckAddrLo], a
    scf
    ret
.match:
    or a
    ret

; --- WriteResultBlock ---
; Writes the 20-byte machine-readable result block described in
; docs/result-format.md to SRAM bank 7 / window B, offset $F00. Call
; once, after the full safe test batch (through EX01/EX02) has
; finished — docs/project-rules.md: "Do not use the result block in a way that
; invalidates the SRAM banking tests."
EXPORT WriteResultBlock
WriteResultBlock:
    call MBC6_EnableRAM
    ld a, 7
    call MBC6_SetRAMBankB
    ld hl, MBC6_SRAM_WIN_B + $F00
    ld a, $4D ; 'M'
    ld [hl+], a
    ld a, $36 ; '6'
    ld [hl+], a
    ld a, $54 ; 'T'
    ld [hl+], a
    ld a, $53 ; 'S'
    ld [hl+], a
    ld a, 1
    ld [hl+], a              ; format_version
    ld a, 1
    ld [hl+], a              ; suite_version
    ld a, [wSummaryPass]
    ld [hl+], a
    ld a, [wSummaryFail]
    ld [hl+], a
    ld a, [wSummarySkip]
    ld [hl+], a
    ld a, [wSummaryInfo]
    ld [hl+], a

    push hl
    call ComputeFailedBitset
    pop hl
    ld a, [wFailedBitset + 0]
    ld [hl+], a
    ld a, [wFailedBitset + 1]
    ld [hl+], a
    ld a, [wFailedBitset + 2]
    ld [hl+], a

    ld a, [wFailureRecorded]
    or a
    jr nz, .haveFailure
    ld a, $FF
    ld [hl+], a              ; first_fail_test_id = none
    xor a
    ld [hl+], a
    xor a
    ld [hl+], a
    xor a
    ld [hl+], a
    xor a
    ld [hl+], a
    xor a
    ld [hl+], a
    jr .checksum
.haveFailure:
    ld a, [wFailTestID]
    ld [hl+], a
    ld a, [wFailBank]
    ld [hl+], a
    ld a, [wFailAddrHi]
    ld [hl+], a
    ld a, [wFailAddrLo]
    ld [hl+], a
    ld a, [wFailExpected]
    ld [hl+], a
    ld a, [wFailActual]
    ld [hl+], a
.checksum:
    push hl                  ; hl is at offset 19, where the checksum goes
    ld hl, MBC6_SRAM_WIN_B + $F00
    ld b, 19
    xor a
.sumLoop:
    add a, [hl]
    inc hl
    dec b
    jr nz, .sumLoop
    pop hl
    ld [hl], a
    ret

; Fills wFailedBitset[0..2] from wTestStatus[0..NUM_TESTS-1]; bit
; (id mod 8) of byte (id / 8) is set when that test's status is FAIL.
ComputeFailedBitset:
    xor a
    ld [wFailedBitset + 0], a
    ld [wFailedBitset + 1], a
    ld [wFailedBitset + 2], a
    ld hl, wTestStatus
    ld b, 0
.loop:
    ld a, b
    cp NUM_TESTS
    jr z, .done
    ld a, [hl+]
    cp RESULT_FAIL
    jr nz, .next
    push hl
    ld a, b
    srl a
    srl a
    srl a                    ; a = byte index (0-2)
    ld c, a
    ld a, b
    and $07                  ; a = bit index (0-7)
    ld l, a
    ld h, 0
    ld de, BitMaskTable
    add hl, de
    ld a, [hl]                ; a = bit mask
    ld hl, wFailedBitset
    ld d, 0
    ld e, c
    add hl, de
    or [hl]
    ld [hl], a
    pop hl
.next:
    inc b
    jr .loop
.done:
    ret

BitMaskTable:
    db $01, $02, $04, $08, $10, $20, $40, $80
