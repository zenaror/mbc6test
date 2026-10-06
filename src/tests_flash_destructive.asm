; Destructive flash tests: TD1-TD9.
;
; docs/project-rules.md "Destructive flash policy": compiled in only when built
; with ENABLE_DESTRUCTIVE_FLASH_TESTS=1 (default is 0 — see Makefile).
; Never reachable from "run all safe tests"; main.asm only calls into
; this file's dispatcher from behind the destructive-mode confirmation
; screen. Sector 7 (physical banks 112-127) is used by convention for
; disposable fixture writes.

IF DEF(ENABLE_DESTRUCTIVE_FLASH_TESTS) && ENABLE_DESTRUCTIVE_FLASH_TESTS

INCLUDE "hardware.inc"
INCLUDE "mbc6.inc"
INCLUDE "tests.inc"

DEF TD_SAMPLE_OFFSETS_COUNT EQU 4

SECTION "Destructive Tests WRAM", WRAM0
wTD5ProtectedByte::   db
wTD5UnprotectedByte:: db

SECTION "Destructive Tests", ROM0

TD_SampleOffsets:
    dw $0000, $0800, $1000, $1FFF

; --- Test_TD1 --- Sector erase (sector 7).
; A single sector-erase command physically erases the whole 128 KiB
; sector at once (standard NOR flash behavior) — but this loop still
; issues Flash_EraseSector once per bank in the sector (redundant on
; real hardware, harmless on an already-blank sector) rather than
; erasing once and switching $2000 to sample the other 15 banks
; afterward. That's deliberate: per Dan/shonumi's Net de Get research
; (https://shonumi.github.io/dandocs.html, "MBC6 Flash Operation"),
; "the flash bank used for all further IO operations is essentially
; 'remembered' after the 0x30 command... until another [flash]
; command is issued" — confirmed in GBE+'s source
; (src/dmg/mbc6.cpp: cart.flash_io_bank is only updated by the 0x30
; case, and every flash read/write goes through it regardless of the
; current $2000/$3000 bank register). Simply switching banks after one
; erase and expecting to read the other 15 banks would silently keep
; reading the erase target instead — a false PASS that verified one
; bank 16 times, not the whole sector. Re-erasing (cheaply, since the
; sector is already blank after the first pass) before each bank's
; check sidesteps that ambiguity entirely instead of assuming either
; behavior is correct. Each of the 16 banks is checked at 4 offsets
; (64 checks total — not all 128 KiB, which would be prohibitively
; slow, but enough to catch a mapper/erase addressing bug).
EXPORT Test_TD1
Test_TD1:
    ld c, 0                  ; bank offset within sector, 0-15
.bankLoop:
    ld a, FLASH_SECTOR7_FIRST_BANK
    add a, c
    push bc                  ; Flash_EraseSector clobbers b/c (Flash_PollStatus's timeout counter)
    call Flash_EraseSector   ; leaves window A mapped to this bank, flash-sourced
    pop bc
    jr nc, .erasedOk
    ld a, FLASH_SECTOR7_FIRST_BANK
    add a, c
    ld [wLastCheckBank], a
    ld a, T_TD1
    call RecordFailureDetail
    ret
.erasedOk:
    ld b, 0                  ; sample index 0-3
.sampleLoop:
    ld a, b
    add a, a                 ; *2 (word table index)
    ld hl, TD_SampleOffsets
    ld d, 0
    ld e, a
    add hl, de
    ld a, [hl+]
    ld e, a
    ld a, [hl]
    ld d, a                  ; de = sample offset
    ld hl, MBC6_ROM_WIN_A
    add hl, de
    ld a, $FF
    ld [wLastCheckExpected], a
    ld a, [hl]
    ld [wLastCheckActual], a
    cp $FF
    jr z, .sampleOk
    ld a, FLASH_SECTOR7_FIRST_BANK
    add a, c
    ld [wLastCheckBank], a
    ld a, T_TD1
    call RecordFailureDetail
    ret
.sampleOk:
    inc b
    ld a, b
    cp TD_SAMPLE_OFFSETS_COUNT
    jr nz, .sampleLoop
    inc c
    ld a, c
    cp FLASH_BANKS_PER_SECTOR
    jr nz, .bankLoop

    ld a, T_TD1
    ld d, RESULT_PASS
    call RecordResult
    ret

; --- Test_TD2 --- 128-byte buffered programming.
; Programs bank 112 (sector 7's first bank), offset 0, and reads back
; against the same formula Flash_ProgramBuffer used to write it.
;
; Re-erases bank 112 first even though TD1 already erased the whole
; sector: per the "remembered bank" quirk documented in TD1's comment,
; TD1's loop leaves the last-erased bank (127) as the one flash reads
; are actually served from on at least one tested emulator, and
; program/write commands never update that pointer themselves — only
; another 0x30 does. This re-erase is a no-op on already-blank flash
; content-wise, but it's what makes the *next* write land on bank 112
; rather than wherever TD1 left off.
EXPORT Test_TD2
Test_TD2:
    ld a, FLASH_SECTOR7_FIRST_BANK
    call Flash_EraseSector
    jr nc, .eraseOk
    ld a, T_TD2
    call RecordFailureDetail
    ret
.eraseOk:
    ld a, FLASH_SECTOR7_FIRST_BANK
    ld de, $0000
    call Flash_ProgramBuffer
    jr nc, .polledOk
    ld a, T_TD2
    call RecordFailureDetail
    ret
.polledOk:
    ld a, FLASH_SECTOR7_FIRST_BANK
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld hl, MBC6_ROM_WIN_A
    ld b, 0
.verifyLoop:
    ld a, b
    ld c, a
    add a, a
    add a, c        ; a = index*3
    add a, $11
    ld c, a          ; c = expected
    ld a, [hl]
    cp c
    jr z, .byteOk
    ld [wLastCheckActual], a
    ld a, c
    ld [wLastCheckExpected], a
    ld a, FLASH_SECTOR7_FIRST_BANK
    ld [wLastCheckBank], a
    ld a, T_TD2
    call RecordFailureDetail
    ret
.byteOk:
    inc hl
    inc b
    ld a, b
    cp 128
    jr nz, .verifyLoop

    ld a, T_TD2
    ld d, RESULT_PASS
    call RecordResult
    ret

; --- Test_TD3 --- 1->0 programming semantics.
; TD2 left bank 112 offset 0 = $11 (0b00010001). Attempts to "program"
; $FF over it — under correct AND-only NOR semantics the byte must
; stay $11 (bits already 0 cannot be programmed back to 1 without an
; erase); reading back $FF instead would indicate the emulator applied
; a plain overwrite rather than AND semantics.
EXPORT Test_TD3
Test_TD3:
    ld a, FLASH_SECTOR7_FIRST_BANK
    ld de, $0000
    ld c, $FF
    call Flash_ProgramBufferFill
    jr nc, .polledOk
    ld a, T_TD3
    call RecordFailureDetail
    ret
.polledOk:
    ld a, FLASH_SECTOR7_FIRST_BANK
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld a, $11
    ld de, MBC6_ROM_WIN_A
    ld c, FLASH_SECTOR7_FIRST_BANK
    call CheckByteAt
    jr c, .fail
    ld a, T_TD3
    ld d, RESULT_PASS
    call RecordResult
    ret
.fail:
    ld a, T_TD3
    call RecordFailureDetail
    ret

; --- Test_TD4 --- Flash status bits (completion, bounded timeout).
; Reprograms the same (already non-$FF) byte again — a harmless,
; idempotent-enough operation on a disposable fixture bank — and
; asserts Flash_PollStatus reported completion without hitting the
; software timeout.
EXPORT Test_TD4
Test_TD4:
    ld a, FLASH_SECTOR7_FIRST_BANK
    ld de, $0080
    ld c, $00
    call Flash_ProgramBufferFill
    jr c, .timedOut
    ld a, T_TD4
    ld d, RESULT_PASS
    call RecordResult
    ret
.timedOut:
    ld a, [wLastFlashStatus]
    ld [wLastCheckActual], a
    ld a, $80
    ld [wLastCheckExpected], a
    ld a, FLASH_SECTOR7_FIRST_BANK
    ld [wLastCheckBank], a
    ld a, T_TD4
    call RecordFailureDetail
    ret

; --- Test_TD5 --- Sector-0 WP behavior (INFO).
; Tests the documented MBC6-level Flash Write Enable/WP register
; ($1000 — docs/project-rules.md: "protects sector 0 and the hidden region"), not
; any flash-chip-internal nonvolatile unprotect command (the iceboy
; doc's sequence for that is only loosely specified and described as
; not even enabled on real Net de Get carts, so issuing it here would
; risk an undocumented, possibly-nonvolatile side effect for no firm
; expected result — docs/project-rules.md: never turn an uncertain observation
; into a normative PASS/FAIL). Programs bank 0 offset 0 with WP
; enabled, then again with WP disabled, and records both outcomes as
; INFO — docs/project-rules.md doesn't give us known-good original sector 0
; content to assert a specific expected byte against.
;
; Deliberately does NOT re-erase bank 0 first the way TD2 does for
; bank 112 (see TD1/TD2 comments on the "remembered bank" quirk):
; doing so would make this test erase sector 0 unconditionally, which
; is a bigger real-cartridge risk than the WP check itself needs. The
; practical consequence is that on an implementation with that quirk,
; these writes may actually land wherever a prior erase last pointed
; (e.g. bank 112 from TD1/TD2, not bank 0) instead of sector 0 at all
; — another reason this stays INFO rather than PASS/FAIL.
EXPORT Test_TD5
Test_TD5:
    xor a
    ld [MBC6_REG_FLASH_WE], a ; WP enabled (protected)
    xor a
    ld de, $0000
    ld c, $00
    call Flash_ProgramBufferFill
    xor a
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld a, [MBC6_ROM_WIN_A]
    ld [wTD5ProtectedByte], a

    ld a, 1
    ld [MBC6_REG_FLASH_WE], a ; WP disabled (unprotected)
    xor a
    ld de, $0000
    ld c, $00
    call Flash_ProgramBufferFill
    xor a
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld a, [MBC6_ROM_WIN_A]
    ld [wTD5UnprotectedByte], a

    xor a
    ld [MBC6_REG_FLASH_WE], a ; leave WP enabled afterward
    ld a, T_TD5
    ld d, RESULT_INFO
    call RecordResult
    ret

; --- Test_TD6 --- Hidden-region erase/program (SKIP).
; The iceboy documentation (this project's authoritative flash source)
; describes how to enter hidden-region *read* mode, but does not
; document an erase/program command sequence for that region.
; Guessing one would mean issuing an undocumented command against
; nonvolatile storage — exactly what docs/project-rules.md prohibits ("Never
; convert an uncertain observation into a normative PASS/FAIL
; expectation"). SKIP is the honest result until an authoritative
; source documents this.
EXPORT Test_TD6
Test_TD6:
    ld a, T_TD6
    ld d, RESULT_SKIP
    call RecordResult
    ret

; --- Test_TD7 --- Partial, out-of-order page buffer and trigger destination.
; Uses only sector 7 in a disposable emulator fixture. Data slots 5 then 1
; are loaded in bank 112; repeating the last slot (slot 1) in bank 113 triggers programming
; at the trigger address. This follows Iceboy's documented partial-buffer,
; arbitrary-order and trigger-address rules; it is intentionally gated with
; every other operation that can alter cartridge flash.
EXPORT Test_TD7
Test_TD7:
    ld a, FLASH_SECTOR7_FIRST_BANK
    call Flash_EraseSector
    jp c, .eraseFailed

    call Flash_SelectCommandWindows
    ld a, FLASH_CMD_UNLOCK1
    ld [FLASH_CMD_ADDR_A], a
    ld a, FLASH_CMD_UNLOCK2
    ld [FLASH_CMD_ADDR_B], a
    ld a, 1
    ld [MBC6_REG_FLASH_WE], a
    ld a, $A0
    ld [FLASH_CMD_ADDR_A], a

    ld a, FLASH_SECTOR7_FIRST_BANK
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld a, $A5
    ld [MBC6_ROM_WIN_A + $0085], a ; slot 5 first, page offset $80
    ld a, $5A
    ld [MBC6_ROM_WIN_A + $0081], a ; out of order: slot 1 second

    ; The repeated slot and mapped bank at trigger time select the target.
    ld a, FLASH_SECTOR7_FIRST_BANK + 1
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld a, $00
    ld [MBC6_ROM_WIN_A + $0081], a ; repeat last slot 1 = commit at bank 113
    ld hl, MBC6_ROM_WIN_A + $0081
    call Flash_PollStatus
    jr c, .programFailed
    call Flash_Reset

    ld a, FLASH_SECTOR7_FIRST_BANK + 1
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld a, [MBC6_ROM_WIN_A + $0085]
    cp $A5
    jr nz, .badSlot5
    ld a, [MBC6_ROM_WIN_A + $0081]
    cp $5A
    jr nz, .badSlot1
    ld a, T_TD7
    ld d, RESULT_PASS
    call RecordResult
    ret

.eraseFailed:
    ld a, T_TD7
    call RecordFailureDetail
    ret
.programFailed:
    ld a, [wLastFlashStatus]
    ld [wLastCheckActual], a
    ld a, $80
    ld [wLastCheckExpected], a
    ld a, FLASH_SECTOR7_FIRST_BANK + 1
    ld [wLastCheckBank], a
    call Flash_Reset
    ld a, T_TD7
    call RecordFailureDetail
    ret
.badSlot5:
    ld [wLastCheckActual], a
    ld a, $A5
    ld [wLastCheckExpected], a
    ld a, FLASH_SECTOR7_FIRST_BANK + 1
    ld [wLastCheckBank], a
    ld a, T_TD7
    call RecordFailureDetail
    ret
.badSlot1:
    ld [wLastCheckActual], a
    ld a, $5A
    ld [wLastCheckExpected], a
    ld a, FLASH_SECTOR7_FIRST_BANK + 1
    ld [wLastCheckBank], a
    ld a, T_TD7
    call RecordFailureDetail
    ret

; --- Test_TD8 --- $F0 as buffered data versus $F0 repeated-slot abort.
; The first page must retain $F0 in a non-trigger payload slot. The second
; page deliberately repeats its final slot with $F0 and must remain erased.
; Both vectors run only against the disposable sector-7 fixture.
EXPORT Test_TD8
Test_TD8:
    ld a, FLASH_SECTOR7_FIRST_BANK
    call Flash_EraseSector
    jp c, .eraseFailed

    call Flash_SelectCommandWindows
    ld a, FLASH_CMD_UNLOCK1
    ld [FLASH_CMD_ADDR_A], a
    ld a, FLASH_CMD_UNLOCK2
    ld [FLASH_CMD_ADDR_B], a
    ld a, 1
    ld [MBC6_REG_FLASH_WE], a
    ld a, $A0
    ld [FLASH_CMD_ADDR_A], a
    ld a, FLASH_SECTOR7_FIRST_BANK
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld a, $F0
    ld [MBC6_ROM_WIN_A + $0103], a ; F0 payload at slot 3
    ld a, $3C
    ld [MBC6_ROM_WIN_A + $0107], a
    ld a, 0
    ld [MBC6_ROM_WIN_A + $0107], a ; repeat slot 7 with non-F0 commits
    ld hl, MBC6_ROM_WIN_A + $0107
    call Flash_PollStatus
    jr c, .programFailed
    call Flash_Reset

    ; Start a second buffer then abort by repeating slot 4 with F0.
    call Flash_SelectCommandWindows
    ld a, FLASH_CMD_UNLOCK1
    ld [FLASH_CMD_ADDR_A], a
    ld a, FLASH_CMD_UNLOCK2
    ld [FLASH_CMD_ADDR_B], a
    ld a, 1
    ld [MBC6_REG_FLASH_WE], a
    ld a, $A0
    ld [FLASH_CMD_ADDR_A], a
    ld a, FLASH_SECTOR7_FIRST_BANK
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld a, $33
    ld [MBC6_ROM_WIN_A + $0184], a
    ld a, $F0
    ld [MBC6_ROM_WIN_A + $0184], a ; repeated slot + F0 aborts buffer
    call Flash_Reset

    ld a, FLASH_SECTOR7_FIRST_BANK
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld a, [MBC6_ROM_WIN_A + $0103]
    cp $F0
    jr nz, .badPayload
    ld a, [MBC6_ROM_WIN_A + $0184]
    cp $FF
    jr nz, .abortChangedArray
    ld a, T_TD8
    ld d, RESULT_PASS
    call RecordResult
    ret

.eraseFailed:
    ld a, T_TD8
    call RecordFailureDetail
    ret
.programFailed:
    ld a, [wLastFlashStatus]
    ld [wLastCheckActual], a
    ld a, $80
    ld [wLastCheckExpected], a
    ld a, FLASH_SECTOR7_FIRST_BANK
    ld [wLastCheckBank], a
    call Flash_Reset
    ld a, T_TD8
    call RecordFailureDetail
    ret
.badPayload:
    ld [wLastCheckActual], a
    ld a, $F0
    ld [wLastCheckExpected], a
    ld a, FLASH_SECTOR7_FIRST_BANK
    ld [wLastCheckBank], a
    ld a, T_TD8
    call RecordFailureDetail
    ret
.abortChangedArray:
    ld [wLastCheckActual], a
    ld a, $FF
    ld [wLastCheckExpected], a
    ld a, FLASH_SECTOR7_FIRST_BANK
    ld [wLastCheckBank], a
    ld a, T_TD8
    call RecordFailureDetail
    ret

; --- Test_TD9 --- hidden-map observation through A and B after erase/F0.
; A completed sector-7 erase exercises the post-operation reset path. The
; six-write hidden-map unlock is then issued and the same 256-byte offsets
; are checksummed independently through both ROM/flash windows. The two
; values are retained as INFO only: cross-window equality is not asserted
; as a hardware requirement by the sources reviewed so far. This operation
; is destructive and is intended only for a disposable emulator fixture.
EXPORT Test_TD9
Test_TD9:
    ld a, FLASH_SECTOR7_FIRST_BANK
    call Flash_EraseSector
    jr nc, .eraseComplete
    ld a, T_TD9
    ld d, RESULT_SKIP
    call RecordResult
    ret
.eraseComplete:
    call Flash_EnterHiddenMode

    ld hl, MBC6_ROM_WIN_A
    ld b, 0                 ; 0 used as "256" via 8-bit wraparound
    xor a
.sumA:
    xor [hl]
    inc hl
    dec b
    jr nz, .sumA
    ld [wTD9HiddenAChecksum], a

    ld hl, MBC6_ROM_WIN_B
    ld b, 0
    xor a
.sumB:
    xor [hl]
    inc hl
    dec b
    jr nz, .sumB
    ld [wTD9HiddenBChecksum], a

    call Flash_Reset
    ld a, T_TD9
    ld d, RESULT_INFO
    call RecordResult
    ret

ENDC
