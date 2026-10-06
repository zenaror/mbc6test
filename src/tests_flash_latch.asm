; Exploratory erase-bank latch lifetime. No normative comparison of reads
; after F0, remapping or enable cycling. See docs/flash-latch-fixture.md.
INCLUDE "hardware.inc"
INCLUDE "mbc6.inc"

IF DEF(ENABLE_FLASH_LATCH_FIXTURE) && ENABLE_FLASH_LATCH_FIXTURE
    ASSERT ENABLE_DESTRUCTIVE_FLASH_TESTS && ENABLE_MGBA_FLASH_FIXTURE_TESTS
    ASSERT !ENABLE_NETDEGET_OFFLINE_FIXTURE

SECTION "Latch observation WRAM", WRAM0
wLatchRecord:: ds 4
wLatchFormat:: db
wLatchStatus:: db ; 3 INFO, 2 SKIP, 1 operational FAIL, 0 NOT RUN
wLatchPhase:: db
wLatchEraseBank:: db
wLatchOtherBank:: db
wLatchBaselineB05:: db
wLatchBaselineB44:: db
wLatchBaselineA05:: db
wLatchBaselineA44:: db
wLatchBusy:: db
wLatchReady:: db
wLatchContinuousB05:: db
wLatchContinuousB44:: db
wLatchContinuousA05:: db
wLatchContinuousA44:: db
wLatchCycledB05:: db
wLatchCycledB44:: db
wLatchCycledA05:: db
wLatchCycledA44:: db
wLatchNewOpcodeB05:: db
wLatchNewOpcodeB44:: db
wLatchRestored:: db
wLatchMarkerMatched:: db
    ds 4
wLatchChecksum:: db
wLatchRecordEnd::
    ASSERT wLatchRecordEnd - wLatchRecord == 32
wLatchDone:: db

SECTION "Latch observation", ROM0
Latch_Init::
    xor a
    ld [wLatchDone], a
    ld hl, wLatchRecord
    ld b, 32
.clear:
    ld [hl+], a
    dec b
    jr nz, .clear
    ld hl, LatchMagic
    ld de, wLatchRecord
    ld b, 4
.magic:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .magic
    ld a, 1
    ld [wLatchFormat], a
    ld a, FLASH_SECTOR7_FIRST_BANK
    ld [wLatchEraseBank], a
    ld a, 96 ; sector6: survives erasing all of sector7
    ld [wLatchOtherBank], a
    ret

Test_FlashEnableLatch::
    call Latch_Init
    ld a, 1
    ld [wLatchPhase], a
    ld [wLatchStatus], a ; operational FAIL unless the full observation finishes
    call Flash_EnterHiddenMode
    ld hl, $40F0
    ld de, LatchMarker
    ld b, 16
.marker:
    ld a, [de]
    cp [hl]
    jr nz, .noMarker
    inc de
    inc hl
    dec b
    jr nz, .marker
    ld a, 1
    ld [wLatchMarkerMatched], a
    call Flash_Reset
    ld a, 2
    ld [wLatchPhase], a
    call Latch_MapOther
    ld de, wLatchBaselineB05
    call Latch_SampleWindows

    ld a, 3
    ld [wLatchPhase], a
    call Flash_LatchStartEraseB
    ld a, [hl]
    ld [wLatchBusy], a
    call Flash_PollStatus
    ld a, [wLastFlashStatus]
    ld [wLatchReady], a
    jr c, .timeout
    ; IMPORTANT: no Flash_Reset/SelectCommandWindows/enable writes here.
    ; F0 stays in B (the operation window), then only mapping changes.
    ld a, FLASH_CMD_RESET
    ld [$6000], a
    xor a
    ld [MBC6_REG_FLASH_WE], a
    ld a, 4
    ld [wLatchPhase], a
    call Latch_MapOther
    ld de, wLatchContinuousB05
    call Latch_SampleWindows

    ld a, 5
    ld [wLatchPhase], a
    call Flash_LatchCycleEnable
    ; Re-select source/bank exactly as in an enable-and-map caller.
    ; This emits no new chip opcode between the two observation points.
    call Latch_MapOther
    ld de, wLatchCycledB05
    call Latch_SampleWindows

    ld a, 6
    ld [wLatchPhase], a
    call Flash_LatchIDResetB
    call Latch_MapOther
    ld a, [$6005]
    ld [wLatchNewOpcodeB05], a
    ld a, [$6044]
    ld [wLatchNewOpcodeB44], a
    ld a, 3 ; completed observation is INFO regardless of raw read values
    ld [wLatchStatus], a
    ld a, 7
    ld [wLatchPhase], a
    jr Latch_Finish
.noMarker:
    call Flash_Reset
    ld a, 2
    ld [wLatchStatus], a
    jr Latch_Finish
.timeout:
    call Flash_Reset ; full Iceboy recovery only after observation aborted
    ; Phase3 and last status identify bounded erase timeout.
    jr Latch_Finish

Latch_MapOther:
    ld a, 96
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld a, 96
    call MBC6_SetROMBankB
    jp MBC6_SelectFlashB

; DE points to contiguous B05/B44/A05/A44 bytes in the result.
Latch_SampleWindows:
    ld a, [$6005]
    ld [de], a
    inc de
    ld a, [$6044]
    ld [de], a
    inc de
    ld a, [$4005]
    ld [de], a
    inc de
    ld a, [$4044]
    ld [de], a
    ret

Latch_Finish:
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
    ld [wLatchRestored], a ; cleanup performed, not a silicon latch assertion
    ld hl, wLatchRecord
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
    ld hl, wLatchRecord
    ld de, $BF60
    ld b, 32
.save:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .save
    call MBC6_DisableRAM
    ld a, 1
    ld [wLatchDone], a
    ret

LatchMagic: db "M6FL"
LatchMarker: db "M6LATCHFIXTUREON"
    ASSERT @ - LatchMarker == 16
ENDC
