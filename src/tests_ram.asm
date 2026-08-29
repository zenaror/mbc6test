; SRAM tests: T20-T24.
; See docs/test-matrix.md and CLAUDE.md "SRAM testing" / "Required
; safe tests". All routines run from fixed ROM (they write MBC6
; registers).
;
; Ordering matters: T21 and T22 populate every physical 4 KiB SRAM
; bank (0-7) with SRAMPatternByte(bank, idx) at two offsets each.
; Because both SRAM windows draw from the same shared 8-bank pool
; (CLAUDE.md's SRAM Bank A/B registers both index the one 32 KiB
; SRAM), T23 and T24 deliberately re-use that already-written data
; instead of writing their own — main.asm's dispatcher must therefore
; run T20, T21, T22, T23, T24 in that order.

INCLUDE "hardware.inc"
INCLUDE "mbc6.inc"
INCLUDE "tests.inc"

DEF SRAM_OFF_LOW  EQU $000
DEF SRAM_OFF_HIGH EQU $FFF

SECTION "T24 WRAM", WRAM0
wT24_BankN:     db
wT24_BankN1:    db
wT24_PairsLeft: db

SECTION "SRAM Tests", ROM0

; --- SRAMPatternByte ---
; Input: b = SRAM bank (0-7), c = offset index (0 = low offset, 1 =
; high offset). Output: a = ($11 + bank*25 + idx*7) & $FF — a
; deterministic, bank- and offset-unique byte.
; Clobbers: a, d, e. Preserves b, c.
EXPORT SRAMPatternByte
SRAMPatternByte:
    ld e, $11
    ld d, b
.bankLoop:
    ld a, d
    or a
    jr z, .bankDone
    ld a, e
    add a, 25
    ld e, a
    dec d
    jr .bankLoop
.bankDone:
    ld d, c
.idxLoop:
    ld a, d
    or a
    jr z, .idxDone
    ld a, e
    add a, 7
    ld e, a
    dec d
    jr .idxLoop
.idxDone:
    ld a, e
    ret

; --- Test_T20 --- SRAM disabled behavior.
; Only tests what is actually documented: RAM-enable gating writes.
; Does not assume any particular open-bus read value while disabled
; (CLAUDE.md: "Do not require a specific open-bus byte if SRAM is
; disabled unless authoritative documentation defines it").
EXPORT Test_T20
Test_T20:
    call MBC6_EnableRAM
    xor a
    call MBC6_SetRAMBankA
    ld a, $A5
    ld hl, MBC6_SRAM_WIN_A
    ld [hl], a

    call MBC6_DisableRAM
    ld a, $5A
    ld [hl], a              ; attempted write while disabled

    call MBC6_EnableRAM
    ld a, $A5
    ld de, MBC6_SRAM_WIN_A
    ld c, 0
    call CheckByteAt
    jr c, .fail

    ld a, T_20
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    ld a, T_20
    call RecordFailureDetail
    ret

; --- Test_T21 --- SRAM Bank A sweep, banks 0-7, two offsets each.
; Writes all banks first, then verifies all banks, so a bank's data
; must have survived every intervening bank switch (CLAUDE.md:
; "Confirm that values survive bank switches during the same run").
EXPORT Test_T21
Test_T21:
    call MBC6_EnableRAM
    ld b, 0
.writeLoop:
    ld a, b
    call MBC6_SetRAMBankA
    ld c, 0
    call SRAMPatternByte
    ld hl, MBC6_SRAM_WIN_A + SRAM_OFF_LOW
    ld [hl], a
    ld c, 1
    call SRAMPatternByte
    ld hl, MBC6_SRAM_WIN_A + SRAM_OFF_HIGH
    ld [hl], a
    inc b
    ld a, b
    cp MBC6_SRAM_BANK_COUNT
    jr nz, .writeLoop

    ld b, 0
.verifyLoop:
    ld a, b
    call MBC6_SetRAMBankA
    ld c, 0
    call SRAMPatternByte
    ld de, MBC6_SRAM_WIN_A + SRAM_OFF_LOW
    ld c, b
    call CheckByteAt
    jr c, .fail
    ld c, 1
    call SRAMPatternByte
    ld de, MBC6_SRAM_WIN_A + SRAM_OFF_HIGH
    ld c, b
    call CheckByteAt
    jr c, .fail
    inc b
    ld a, b
    cp MBC6_SRAM_BANK_COUNT
    jr nz, .verifyLoop

    ld a, T_21
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    ld a, T_21
    call RecordFailureDetail
    ret

; --- Test_T22 --- SRAM Bank B sweep, banks 0-7, two offsets each.
; Same physical 8-bank pool as T21 (see file header comment); this
; independently proves window B maps into it correctly.
EXPORT Test_T22
Test_T22:
    call MBC6_EnableRAM
    ld b, 0
.writeLoop:
    ld a, b
    call MBC6_SetRAMBankB
    ld c, 0
    call SRAMPatternByte
    ld hl, MBC6_SRAM_WIN_B + SRAM_OFF_LOW
    ld [hl], a
    ld c, 1
    call SRAMPatternByte
    ld hl, MBC6_SRAM_WIN_B + SRAM_OFF_HIGH
    ld [hl], a
    inc b
    ld a, b
    cp MBC6_SRAM_BANK_COUNT
    jr nz, .writeLoop

    ld b, 0
.verifyLoop:
    ld a, b
    call MBC6_SetRAMBankB
    ld c, 0
    call SRAMPatternByte
    ld de, MBC6_SRAM_WIN_B + SRAM_OFF_LOW
    ld c, b
    call CheckByteAt
    jr c, .fail
    ld c, 1
    call SRAMPatternByte
    ld de, MBC6_SRAM_WIN_B + SRAM_OFF_HIGH
    ld c, b
    call CheckByteAt
    jr c, .fail
    inc b
    ld a, b
    cp MBC6_SRAM_BANK_COUNT
    jr nz, .verifyLoop

    ld a, T_22
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    ld a, T_22
    call RecordFailureDetail
    ret

; --- Test_T23 --- SRAM A/B independence.
; Relies on T21/T22 having already populated every bank at
; SRAM_OFF_LOW with SRAMPatternByte(bank, 0) — see file header.
EXPORT Test_T23
Test_T23:
    call MBC6_EnableRAM
    ld a, 2
    call MBC6_SetRAMBankA
    ld a, 5
    call MBC6_SetRAMBankB

    ld b, 2
    ld c, 0
    call SRAMPatternByte
    ld de, MBC6_SRAM_WIN_A + SRAM_OFF_LOW
    ld c, 2
    call CheckByteAt
    jr c, .fail

    ld b, 5
    ld c, 0
    call SRAMPatternByte
    ld de, MBC6_SRAM_WIN_B + SRAM_OFF_LOW
    ld c, 5
    call CheckByteAt
    jr c, .fail

    ; Change only B; A (bank 2) must be unaffected.
    ld a, 7
    call MBC6_SetRAMBankB
    ld b, 2
    ld c, 0
    call SRAMPatternByte
    ld de, MBC6_SRAM_WIN_A + SRAM_OFF_LOW
    ld c, 2
    call CheckByteAt
    jr c, .fail
    ld b, 7
    ld c, 0
    call SRAMPatternByte
    ld de, MBC6_SRAM_WIN_B + SRAM_OFF_LOW
    ld c, 7
    call CheckByteAt
    jr c, .fail

    ; Change only A; B (still bank 7) must be unaffected.
    ld a, 4
    call MBC6_SetRAMBankA
    ld b, 7
    ld c, 0
    call SRAMPatternByte
    ld de, MBC6_SRAM_WIN_B + SRAM_OFF_LOW
    ld c, 7
    call CheckByteAt
    jr c, .fail
    ld b, 4
    ld c, 0
    call SRAMPatternByte
    ld de, MBC6_SRAM_WIN_A + SRAM_OFF_LOW
    ld c, 4
    call CheckByteAt
    jr c, .fail

    ld a, T_23
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    ld a, T_23
    call RecordFailureDetail
    ret

; --- Test_T24 --- SRAM 4 KiB granularity.
; For a few adjacent bank pairs (N, N+1), confirms bank N's high
; offset and bank N+1's low offset are independently addressable (not
; aliased into one 8 KiB block the way ROM banking would suggest),
; and that visiting N+1 does not disturb N. Relies on T21's sweep data.
T24_Pairs:
    db 0, 1
    db 3, 4
    db 6, 7
DEF T24_PAIR_COUNT EQU 3

EXPORT Test_T24
Test_T24:
    call MBC6_EnableRAM
    ld hl, T24_Pairs
    ld a, T24_PAIR_COUNT
    ld [wT24_PairsLeft], a
.pairLoop:
    ld a, [hl+]
    ld [wT24_BankN], a
    ld a, [hl+]
    ld [wT24_BankN1], a
    push hl
    call T24_CheckPair
    pop hl
    jr c, .fail
    ; T24_CheckPair uses b/c internally, so the pair-remaining counter
    ; must live in WRAM rather than a register that would collide.
    ld a, [wT24_PairsLeft]
    dec a
    ld [wT24_PairsLeft], a
    jr nz, .pairLoop
    ld a, T_24
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    ld a, T_24
    call RecordFailureDetail
    ret

T24_CheckPair:
    ld a, [wT24_BankN]
    call MBC6_SetRAMBankA
    ld a, [wT24_BankN]
    ld b, a
    ld c, 1
    call SRAMPatternByte
    ld de, MBC6_SRAM_WIN_A + SRAM_OFF_HIGH
    ld c, b
    call CheckByteAt
    ret c

    ld a, [wT24_BankN1]
    call MBC6_SetRAMBankA
    ld a, [wT24_BankN1]
    ld b, a
    ld c, 0
    call SRAMPatternByte
    ld de, MBC6_SRAM_WIN_A + SRAM_OFF_LOW
    ld c, b
    call CheckByteAt
    ret c

    ; Re-select bank N: its high offset must be unchanged by visiting N+1.
    ld a, [wT24_BankN]
    call MBC6_SetRAMBankA
    ld a, [wT24_BankN]
    ld b, a
    ld c, 1
    call SRAMPatternByte
    ld de, MBC6_SRAM_WIN_A + SRAM_OFF_HIGH
    ld c, b
    call CheckByteAt
    ret
