; Offline install/reopen fixture with original generated homebrew data.
; Protocol sources: Iceboy Net de Get flash procedures and the host's
; A-window writer at ROM0 $1568 (image SHA in docs/mbc6-reference.md).
; Never assembled into safe or ordinary destructive builds. The marker
; is an additional guard, not proof that physical hardware is disposable.
INCLUDE "hardware.inc"
INCLUDE "mbc6.inc"

IF DEF(ENABLE_NETDEGET_OFFLINE_FIXTURE) && ENABLE_NETDEGET_OFFLINE_FIXTURE
    ASSERT ENABLE_DESTRUCTIVE_FLASH_TESTS && ENABLE_MGBA_FLASH_FIXTURE_TESTS

SECTION "Offline record", WRAM0
wOfflineRecord::
    ds 4 ; M6OF
wOfflineFormat:: db
wOfflineStatus:: db ; 1 PASS, 2 FAIL, 3 SKIP
wOfflinePhase:: db ; 1 marker, 2 resume, 3 erase, 4 program, 5 verify, 6 exec, 7 done
wOfflineMode:: db ; 1 install, 2 reopen
wOfflinePages:: db
wOfflineBusy:: db ; raw last program's first sample, observational
wOfflineReady:: db
wOfflineReceiptA:: db
wOfflineReceiptB:: db
wOfflineSumLo:: db
wOfflineSumHi:: db
wOfflineExpectedSumLo:: db
wOfflineExpectedSumHi:: db
wOfflineFailOffsetLo:: db
wOfflineFailOffsetHi:: db
wOfflineExpected:: db
wOfflineActual:: db
wOfflineRestored:: db
wOfflineMarkerMatched:: db
    ds 8
wOfflineRecordChecksum:: db
wOfflineRecordEnd::
    ASSERT wOfflineRecordEnd - wOfflineRecord == 32
wOfflinePrior: ds 32
wOfflineDone:: db
wOfflineHalf: db
wOfflinePage: db

SECTION "Offline workflow", ROM0
; Initialize before confirmation too: cancelled runs must never display
; stale/uninitialized PASS data. No SRAM/flash mutation in this routine.
Offline_Init::
    xor a
    ld [wOfflineDone], a
    ld hl, wOfflineRecord
    ld b, 32
.clear:
    ld [hl+], a
    dec b
    jr nz, .clear
    ld hl, OfflineMagic
    ld de, wOfflineRecord
    ld b, 4
.magic:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .magic
    ld a, 1
    ld [wOfflineFormat], a
    ret

Test_NetDeGetOffline::
    call Offline_Init
    ld a, 1
    ld [wOfflinePhase], a
    ld a, 2 ; default FAIL until the complete path finishes
    ld [wOfflineStatus], a

    call Flash_EnterHiddenMode
    ld hl, $40F0
    ld de, OfflineMarker
    ld b, 16
.marker:
    ld a, [de]
    cp [hl]
    jp nz, .noMarker
    inc de
    inc hl
    dec b
    jr nz, .marker
    ld a, 1
    ld [wOfflineMarkerMatched], a
    call Flash_Reset

    ; Safe SRAM tests touch only bank-local $000/$FFF, preserving $F20.
    ; A valid completed record requests a read/execute-only reopen.
    call MBC6_EnableRAM
    ld a, 7
    call MBC6_SetRAMBankB
    ld hl, $BF20
    ld de, wOfflinePrior
    ld b, 32
.loadPrior:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .loadPrior
    ld hl, wOfflinePrior
    ld de, OfflineMagic
    ld b, 4
.priorMagic:
    ld a, [de]
    cp [hl]
    jp nz, .install
    inc de
    inc hl
    dec b
    jr nz, .priorMagic
    ld a, 2
    ld [wOfflinePhase], a
    ld [wOfflineMode], a
    ld a, [wOfflinePrior + 4]
    cp 1
    jp nz, Offline_Finish
    ld hl, wOfflinePrior
    ld b, 31
    xor a
.priorSum:
    add [hl]
    inc hl
    dec b
    jr nz, .priorSum
    cp [hl]
    jp nz, Offline_Finish
    ld a, [wOfflinePrior + 5]
    cp 1
    jp nz, Offline_Finish
    ; Only a complete successful install/reopen is a resume receipt.
    ; A checksum alone does not validate the record's field semantics.
    ld a, [wOfflinePrior + 6]
    cp 7
    jp nz, Offline_Finish
    ld a, [wOfflinePrior + 7]
    cp 1
    jr z, .priorInstall
    cp 2
    jp nz, Offline_Finish
    ld a, [wOfflinePrior + 8]
    or a
    jp nz, Offline_Finish
    jr .priorReceipts
.priorInstall:
    ld a, [wOfflinePrior + 8]
    cp 64
    jp nz, Offline_Finish
.priorReceipts:
    ld a, [wOfflinePrior + 11]
    cp $A6
    jp nz, Offline_Finish
    ld a, [wOfflinePrior + 12]
    cp $5A
    jp nz, Offline_Finish
    ld a, [wOfflinePrior + 21]
    cp 1
    jp nz, Offline_Finish
    ld a, [wOfflinePrior + 22]
    cp 1
    jp nz, Offline_Finish
    ld hl, wOfflinePrior + 23
    ld b, 8
.priorReserved:
    ld a, [hl+]
    or a
    jp nz, Offline_Finish
    dec b
    jr nz, .priorReserved
    ld a, [wOfflinePrior + 13]
    ld b, a
    ld a, [wOfflinePrior + 15]
    cp b
    jp nz, Offline_Finish
    ld a, [wOfflinePrior + 14]
    ld b, a
    ld a, [wOfflinePrior + 16]
    cp b
    jp nz, Offline_Finish
    jp .stage

.noMarker:
    call Flash_Reset
    ld a, 3
    ld [wOfflineStatus], a
    jp Offline_Finish

.install:
    ld a, 1
    ld [wOfflineMode], a
    ld a, 3
    ld [wOfflinePhase], a
    ld a, FLASH_SECTOR7_FIRST_BANK
    call Flash_OfflineErase
    jp c, Offline_Finish
    ; Confirm the entire 128 KiB erased sector, including unused banks.
    ld b, FLASH_SECTOR7_FIRST_BANK
.eraseBank:
    ld a, b
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld hl, $4000
.erased:
    ld a, [hl+]
    cp $FF
    jp nz, Offline_Finish
    ld a, h
    cp $60
    jr nz, .erased
    inc b
    ld a, b
    cp 128
    jr nz, .eraseBank
.stage:
    xor a
    ld [wOfflineHalf], a
    ld a, 2
    ldh [rSVBK], a ; staging WRAM bank 2, $D000-$DFFF
.half:
    call Offline_GenerateHalf
    ld a, [wOfflineMode]
    cp 1
    jr nz, .verifyHalf
    ld a, 4
    ld [wOfflinePhase], a
    xor a
    ld [wOfflinePage], a
.page:
    ; One 4 KiB chunk is 32 aligned pages; source and target increment.
    call Offline_PagePointers
    call Flash_OfflineProgramPage
    jp c, Offline_Finish
    ld hl, wOfflinePages
    inc [hl]
    ; Check each completed page with WE low, before the next command.
    call Offline_PagePointers
    ld b, 128
.pageReadback:
    ld a, [de]
    cp [hl]
    jp nz, Offline_Mismatch
    inc de
    inc hl
    dec b
    jr nz, .pageReadback
    ld hl, wOfflinePage
    inc [hl]
    ld a, [hl]
    cp 32
    jr nz, .page
.verifyHalf:
    ld a, 5
    ld [wOfflinePhase], a
    ld a, FLASH_SECTOR7_FIRST_BANK
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld a, FLASH_SECTOR7_FIRST_BANK
    call MBC6_SetROMBankB
    call MBC6_SelectFlashB
    ld hl, $4000
    ld a, [wOfflineHalf]
    or a
    jr z, .halfAddress
    ld h, $50
.halfAddress:
    ld de, $D000
.readback:
    ld a, [de]
    cp [hl]
    jp nz, Offline_Mismatch
    ; Independently compare the corresponding B-window byte.
    ld a, h
    add $20
    ld h, a
    ld a, [de]
    cp [hl]
    jp nz, Offline_Mismatch
    ld a, h
    sub $20
    ld h, a
    ld a, [hl]
    call Offline_AddActual
    inc hl
    inc de
    ld a, d
    cp $E0
    jr nz, .readback
    ld a, [wOfflineHalf]
    or a
    jr nz, .checksum
    inc a
    ld [wOfflineHalf], a
    jp .half
.checksum:
    ld a, [wOfflineExpectedSumLo]
    ld b, a
    ld a, [wOfflineSumLo]
    cp b
    jp nz, Offline_Finish
    ld a, [wOfflineExpectedSumHi]
    ld b, a
    ld a, [wOfflineSumHi]
    cp b
    jp nz, Offline_Finish
    ld a, 6
    ld [wOfflinePhase], a
    ; Original homebrew bytes: only WRAM stores and RET, no mapper writes.
    call $4000
    ld a, [wOfflineReceiptA]
    cp $A6
    jp nz, Offline_Finish
    ld a, [wOfflineReceiptB]
    cp $5A
    jp nz, Offline_Finish
    call Offline_Restore
    ; Verify ROM signatures after returning and restoring both latches.
    ld hl, $5FF0
    ld de, OfflineROMWitnessA
    ld b, 16
.restoredA:
    ld a, [de]
    cp [hl]
    jp nz, Offline_Finish
    inc hl
    inc de
    dec b
    jr nz, .restoredA
    ld hl, $7FF0
    ld de, OfflineROMWitnessB
    ld b, 16
.restoredB:
    ld a, [de]
    cp [hl]
    jp nz, Offline_Finish
    inc hl
    inc de
    dec b
    jr nz, .restoredB
    ld a, 1
    ld [wOfflineRestored], a
    ld [wOfflineStatus], a
    ld a, 7
    ld [wOfflinePhase], a
    jp Offline_Finish

; HL=A destination, DE=bank2 WRAM source for current half/page.
Offline_PagePointers:
    ld a, [wOfflinePage]
    ld e, a
    and 1
    rrca
    ld l, a
    ld a, e
    srl a
    ld h, a
    add $D0
    ld d, a
    ld e, l
    ld a, [wOfflineHalf]
    swap a
    add h
    add $40
    ld h, a
    ret

; Pattern(i) = low(i) XOR high(i) XOR $5A for global offsets0..8191.
; Each half stages 4 KiB; first bytes are replaced with the RET payload.
Offline_GenerateHalf:
    ld a, [wOfflineHalf]
    swap a
    ld d, a
    ld e, 0
    ld hl, $D000
.generate:
    ld a, e
    xor d
    xor $5A
    ld [hl+], a
    inc de
    ld a, h
    cp $E0
    jr nz, .generate
    ld a, [wOfflineHalf]
    or a
    jr nz, .sum
    ld hl, OfflinePayloadTemplate
    ld de, $D000
    ld b, OfflinePayloadTemplateEnd - OfflinePayloadTemplate
.template:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .template
.sum:
    ld hl, $D000
.sumLoop:
    ld a, [hl+]
    ld c, a
    ld a, [wOfflineExpectedSumLo]
    add c
    ld [wOfflineExpectedSumLo], a
    ld a, [wOfflineExpectedSumHi]
    adc 0
    ld [wOfflineExpectedSumHi], a
    ld a, h
    cp $E0
    jr nz, .sumLoop
    ret

Offline_AddActual:
    ld c, a
    ld a, [wOfflineSumLo]
    add c
    ld [wOfflineSumLo], a
    ld a, [wOfflineSumHi]
    adc 0
    ld [wOfflineSumHi], a
    ret

; Expected byte is still at DE, actual at HL. B-window failures are
; normalized to the same bank-local offset; no writes retry on mismatch.
Offline_Mismatch:
    ld a, [de]
    ld [wOfflineExpected], a
    ld a, [hl]
    ld [wOfflineActual], a
    ld a, l
    ld [wOfflineFailOffsetLo], a
    ld a, h
    and $1F
    ld [wOfflineFailOffsetHi], a
    jp Offline_Finish

Offline_Restore:
    xor a
    ld [MBC6_REG_FLASH_WE], a
    call MBC6_SelectROMA
    call MBC6_SelectROMB
    ld a, 2
    call MBC6_SetROMBankA
    ld a, 3
    call MBC6_SetROMBankB
    ld a, 1
    ldh [rSVBK], a
    ret

Offline_Finish:
    call Offline_Restore
    ld hl, wOfflineRecord
    ld b, 31
    xor a
.sum:
    add [hl]
    inc hl
    dec b
    jr nz, .sum
    ld [hl], a
    call MBC6_EnableRAM
    ld a, 7
    call MBC6_SetRAMBankB
    ld hl, wOfflineRecord
    ld de, $BF20
    ld b, 32
.save:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .save
    call MBC6_DisableRAM
    ld a, 1
    ld [wOfflineDone], a
    ret

OfflineMagic: db "M6OF"
OfflineMarker: db "M6OFFLINEFIXTURE"
    ASSERT @ - OfflineMarker == 16

OfflinePayloadTemplate::
    ld a, $A6
    ld [wOfflineReceiptA], a
    ld a, $5A
    ld [wOfflineReceiptB], a
    ret
OfflinePayloadTemplateEnd::

; Same deterministic bank signatures as the generator, banks2/3.
; Explicit witness avoids claiming restoration from source-latch reads.
OfflineROMWitnessA:
    db $4D, $36, $42, $4B, $02, $FD, $A5, $5A, $0D, $FD, $01, $00, $19, $00, $00, $00
OfflineROMWitnessB:
    db $4D, $36, $42, $4B, $03, $FC, $A5, $5A, $10, $FC, $01, $01, $1C, $00, $00, $00
ENDC
