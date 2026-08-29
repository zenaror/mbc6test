; Text UI: CGB palette/tilemap setup, an original 5x7 font loader, a
; plain string printer, and a 3-page results viewer (all 26 tests'
; PASS/FAIL/SKIP/INFO status, a detailed first-failure page, and an
; INFO/experimental page) with A-button paging. This is the ROM's only
; way to show its own results — CLAUDE.md requires the detail to be
; visible on-screen, not just inferable from a summary count.

INCLUDE "hardware.inc"
INCLUDE "tests.inc"

DEF SCRN_WIDTH EQU 32

DEF JOY_RIGHT  EQU %00000001
DEF JOY_LEFT   EQU %00000010
DEF JOY_UP     EQU %00000100
DEF JOY_DOWN   EQU %00001000
DEF JOY_A      EQU %00010000
DEF JOY_B      EQU %00100000
DEF JOY_SELECT EQU %01000000
DEF JOY_START  EQU %10000000

SECTION "UI WRAM", WRAM0
wSummaryLineBuf: ds 21
wFailureLineBuf: ds 21
wGridIndex: db
wCurrentPage: db
wPrevJoypad: db

SECTION "UI", ROM0

; --- UI_Init ---
; LCD off, BG palette 0 = white/black, tilemap + attribute map cleared,
; font loaded into VRAM $8000. Leaves the LCD off.
EXPORT UI_Init
UI_Init:
    xor a
    ldh [rLCDC], a

    ; BG palette 0: color0 = white, color1 = black, color2/3 = black
    ; (unused by this font, filled defensively so no color reads as
    ; garbage if a tile ever addresses them).
    ld a, BCPSF_AUTOINC
    ldh [rBCPS], a
    ld a, $FF
    ldh [rBCPD], a
    ld a, $7F
    ldh [rBCPD], a
    REPT 6
    xor a
    ldh [rBCPD], a
    ENDR

    ; Tile attribute map (VRAM bank 1): force palette 0 / bank 0 tile
    ; data for the whole screen, so printed text never inherits
    ; whatever the boot state (or an emulator skipping the boot ROM)
    ; left behind.
    ld a, 1
    ldh [rVBK], a
    ld hl, _SCRN0
    ld bc, SCRN_WIDTH * 32
.clearAttr:
    xor a
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .clearAttr

    xor a
    ldh [rVBK], a
    ld hl, _SCRN0
    ld bc, SCRN_WIDTH * 32
.clearMap:
    xor a                  ; tile 0 = ' '
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .clearMap

    call LoadFont
    ret

; --- UI_TurnOn ---
; Enables the LCD with BG on, $8000 tile addressing.
EXPORT UI_TurnOn
UI_TurnOn:
    ld a, LCDCF_ON | LCDCF_BGON | LCDCF_BG8000
    ldh [rLCDC], a
    ret

; --- LoadFont ---
; Copies FontTiles (src/font_data.asm, ROM0) into VRAM bank 0 tile
; data at $8000. Must run with the LCD off or during VBlank.
LoadFont:
    ld hl, FontTiles
    ld de, _VRAM8000
    ld bc, FontTilesEnd - FontTiles
.copy:
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .copy
    ret

; --- PrintString ---
; Input: hl = pointer to a null-terminated ASCII string (chars $20-$5A),
;        de = destination tilemap address. Advances hl/de as it goes.
; Tile index = ASCII code - $20 (see tools/gen_font.py).
EXPORT PrintString
PrintString:
    ld a, [hl+]
    or a
    ret z
    sub $20 ; ' ' -> tile index base
    ld [de], a
    inc de
    jr PrintString

; --- PrintFixedChars ---
; Input: hl = source (raw ASCII, not null-terminated), de = dest,
; b = count. Prints exactly b tiles, advancing hl and de by b.
PrintFixedChars:
    ld a, [hl+]
    sub $20
    ld [de], a
    inc de
    dec b
    jr nz, PrintFixedChars
    ret

; --- ByteToDecimal2 ---
; Input: a = value (0-99). Output: b = tens digit ASCII, c = ones digit ASCII.
EXPORT ByteToDecimal2
ByteToDecimal2:
    ld d, 0
.tensLoop:
    cp 10
    jr c, .doneTens
    sub 10
    inc d
    jr .tensLoop
.doneTens:
    ld e, a
    ld a, d
    add $30 ; '0'
    ld b, a
    ld a, e
    add $30 ; '0'
    ld c, a
    ret

; --- ByteToHex2 ---
; Input: a = value. Output: b = high nibble ASCII, c = low nibble ASCII.
; Clobbers: a, l (not d/e — callers may hold a running address in de
; across this call).
EXPORT ByteToHex2
ByteToHex2:
    ld l, a
    swap a
    and $0F
    call .nibble
    ld b, a
    ld a, l
    and $0F
    call .nibble
    ld c, a
    ret
.nibble:
    cp 10
    jr c, .digit
    add $37 ; 'A' - 10
    ret
.digit:
    add $30 ; '0'
    ret

; --- PrintHexByte ---
; Input: a = value, de = dest. Writes 2 tiles (hex digits), advances de by 2.
; Clobbers: a, b, c, l.
PrintHexByte:
    call ByteToHex2
    ld a, b
    sub $20
    ld [de], a
    inc de
    ld a, c
    sub $20
    ld [de], a
    inc de
    ret

; --- ReadJoypad ---
; Output: a = bitmask of currently held buttons, active-high:
; bit0=Right bit1=Left bit2=Up bit3=Down bit4=A bit5=B bit6=Select bit7=Start.
EXPORT ReadJoypad
ReadJoypad:
    ld a, $10          ; P14=1,P15=0: select action buttons
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    swap a
    ld b, a

    ld a, $20          ; P14=0,P15=1: select d-pad
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    or b
    ld b, a

    ld a, $30          ; deselect both
    ldh [rP1], a
    ld a, b
    ret

; --- WaitFrame ---
; Busy-polls rLY for one full frame boundary (not VBlank-interrupt
; driven — this ROM keeps interrupts off throughout).
WaitFrame:
.waitNotVblank:
    ldh a, [rLY]
    cp 144
    jr nc, .waitNotVblank
.waitVblank:
    ldh a, [rLY]
    cp 144
    jr c, .waitVblank
    ret

; --- BuildSummaryLine ---
; Fills wSummaryLineBuf with "P:.. F:.. S:.. I:.." using the current
; wSummary* counters.
EXPORT BuildSummaryLine
BuildSummaryLine:
    ld hl, SummaryTemplate
    ld de, wSummaryLineBuf
    ld bc, SummaryTemplateEnd - SummaryTemplate
.copyTemplate:
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .copyTemplate

    ld a, [wSummaryPass]
    call ByteToDecimal2
    ld a, b
    ld [wSummaryLineBuf + 2], a
    ld a, c
    ld [wSummaryLineBuf + 3], a

    ld a, [wSummaryFail]
    call ByteToDecimal2
    ld a, b
    ld [wSummaryLineBuf + 7], a
    ld a, c
    ld [wSummaryLineBuf + 8], a

    ld a, [wSummarySkip]
    call ByteToDecimal2
    ld a, b
    ld [wSummaryLineBuf + 12], a
    ld a, c
    ld [wSummaryLineBuf + 13], a

    ld a, [wSummaryInfo]
    call ByteToDecimal2
    ld a, b
    ld [wSummaryLineBuf + 17], a
    ld a, c
    ld [wSummaryLineBuf + 18], a
    ret

SummaryTemplate:
    db "P:00 F:00 S:00 I:00", 0
SummaryTemplateEnd:

; --- StatusToTile ---
; Input: a = RESULT_* (or RESULT_NOT_RUN). Output: a = tile index for
; the one-character status glyph P/F/S/I/- .
StatusToTile:
    cp RESULT_PASS
    jr nz, .notPass
    ld a, $30 ; 'P' - $20
    ret
.notPass:
    cp RESULT_FAIL
    jr nz, .notFail
    ld a, $26 ; 'F' - $20
    ret
.notFail:
    cp RESULT_SKIP
    jr nz, .notSkip
    ld a, $33 ; 'S' - $20
    ret
.notSkip:
    cp RESULT_INFO
    jr nz, .notInfo
    ld a, $29 ; 'I' - $20
    ret
.notInfo:
    ld a, $0D ; '-' - $20 (RESULT_NOT_RUN)
    ret

; --- ComputeGridDest ---
; Input: wGridIndex (0-25). Output: de = tilemap address for that
; entry's 3-char name + ':' + status glyph (6-tile slot), 3 slots per
; row starting at row 2, 6 tiles per slot.
ComputeGridDest:
    ld a, [wGridIndex]
    ld b, 0
.divLoop:
    cp 3
    jr c, .divDone
    sub 3
    inc b
    jr .divLoop
.divDone:
    ; a = column index (0-2), b = row offset from row 2
    ld c, a
    add a, a
    add a, c
    add a, a          ; a = column index * 6
    ld e, a
    ld d, 0
    ld hl, _SCRN0 + 2 * SCRN_WIDTH
    add hl, de
    ld a, b
    or a
    jr z, .noRows
.rowLoop:
    ld de, SCRN_WIDTH
    add hl, de
    dec a
    jr nz, .rowLoop
.noRows:
    ld d, h
    ld e, l
    ret

; --- DrawResultsGrid ---
; Title + all NUM_TESTS entries ("Tnn:X") + the summary line.
DrawResultsGrid:
    call UI_Init
    ld hl, ResultsTitleText
    ld de, _SCRN0 + 1
    call PrintString

    xor a
    ld [wGridIndex], a
.entryLoop:
    ; hl = TestShortNames + wGridIndex*3
    ld a, [wGridIndex]
    ld b, a
    ld hl, TestShortNames
    or a
    jr z, .haveNamePtr
.mulLoop:
    inc hl
    inc hl
    inc hl
    dec b
    jr nz, .mulLoop
.haveNamePtr:
    push hl
    call ComputeGridDest      ; de = dest slot start
    pop hl
    ld b, 3
    call PrintFixedChars      ; prints 3-char name, hl+=3, de+=3

    ld a, $1A                 ; ':' tile index ($3A - $20)
    ld [de], a
    inc de

    ld a, [wGridIndex]
    ld l, a
    ld h, 0
    ld bc, wTestStatus
    add hl, bc
    ld a, [hl]
    call StatusToTile
    ld [de], a

    ld a, [wGridIndex]
    inc a
    ld [wGridIndex], a
    cp NUM_TESTS
    jr nz, .entryLoop

    call BuildSummaryLine
    ld hl, wSummaryLineBuf
    ld de, _SCRN0 + 12 * SCRN_WIDTH + 0
    call PrintString

    ld hl, HintNextText
    ld de, _SCRN0 + 14 * SCRN_WIDTH + 0
    call PrintString

    call UI_TurnOn
    ret

ResultsTitleText:
    db "MBC6 TEST RESULTS", 0
HintNextText:
    db "A:NEXT PAGE", 0

; 3 characters per test, in test-ID order (include/tests.inc).
TestShortNames:
    db "T00","T01","T10","T11","T12","T13","T14"
    db "T20","T21","T22","T23","T24"
    db "T30","T31","T32","T33","T34","T35"
    db "EX1","EX2"
    db "TD1","TD2","TD3","TD4","TD5","TD6"

; --- DrawFailurePage ---
; Detailed first-failure record, or a "no failures" message.
DrawFailurePage:
    call UI_Init
    ld hl, FailureTitleText
    ld de, _SCRN0 + 1
    call PrintString

    ld a, [wFailureRecorded]
    or a
    jr nz, .haveFailure

    ld hl, NoFailuresText
    ld de, _SCRN0 + 3 * SCRN_WIDTH + 1
    call PrintString
    jr .doneBody

.haveFailure:
    ld hl, LabelTestID
    ld de, _SCRN0 + 3 * SCRN_WIDTH + 1
    call PrintString
    ld a, [wFailTestID]
    call PrintHexByte

    ld hl, LabelBank
    ld de, _SCRN0 + 5 * SCRN_WIDTH + 1
    call PrintString
    ld a, [wFailBank]
    call PrintHexByte

    ld hl, LabelAddr
    ld de, _SCRN0 + 7 * SCRN_WIDTH + 1
    call PrintString
    ld a, [wFailAddrHi]
    call PrintHexByte
    ld a, [wFailAddrLo]
    call PrintHexByte

    ld hl, LabelExpected
    ld de, _SCRN0 + 9 * SCRN_WIDTH + 1
    call PrintString
    ld a, [wFailExpected]
    call PrintHexByte

    ld hl, LabelActual
    ld de, _SCRN0 + 11 * SCRN_WIDTH + 1
    call PrintString
    ld a, [wFailActual]
    call PrintHexByte

.doneBody:
    ld hl, HintNextText
    ld de, _SCRN0 + 14 * SCRN_WIDTH + 0
    call PrintString
    call UI_TurnOn
    ret

FailureTitleText:
    db "FAILURE DETAIL", 0
NoFailuresText:
    db "NO FAILURES", 0
LabelTestID:
    db "TEST ID = $", 0
LabelBank:
    db "BANK    = $", 0
LabelAddr:
    db "ADDRESS = $", 0
LabelExpected:
    db "EXPECTED= $", 0
LabelActual:
    db "ACTUAL  = $", 0

; --- DrawInfoPage ---
; INFO/experimental observations: T34's hidden-region checksum, T35's
; observed sector-0 status byte, EX01's first bytes at bank $FF, and
; EX02's ROM-vs-other outcome flag. None of these are PASS/FAIL —
; CLAUDE.md "Undefined / experimental behavior".
DrawInfoPage:
    call UI_Init
    ld hl, InfoTitleText
    ld de, _SCRN0 + 1
    call PrintString

    ld hl, LabelT34
    ld de, _SCRN0 + 2 * SCRN_WIDTH + 0
    call PrintString
    ld a, [wHiddenRegionChecksum]
    call PrintHexByte

    ld hl, LabelT35
    ld de, _SCRN0 + 4 * SCRN_WIDTH + 0
    call PrintString
    ld a, [wSector0StatusByte]
    call PrintHexByte

    ld hl, LabelEx1
    ld de, _SCRN0 + 6 * SCRN_WIDTH + 0
    call PrintString
    ld hl, wEx01Observed
    ld de, _SCRN0 + 7 * SCRN_WIDTH + 1
    ld b, 4
.ex1Loop:
    push bc
    ld a, [hl+]
    push hl
    call PrintHexByte
    ld a, 0            ; tile 0 = space, separator
    ld [de], a
    inc de
    pop hl
    pop bc
    dec b
    jr nz, .ex1Loop

    ld hl, LabelEx2
    ld de, _SCRN0 + 9 * SCRN_WIDTH + 0
    call PrintString
    ld a, [wEx02Observed]
    call PrintHexByte

    ld hl, HintBackText
    ld de, _SCRN0 + 14 * SCRN_WIDTH + 0
    call PrintString
    call UI_TurnOn
    ret

InfoTitleText:
    db "INFO / EXPERIMENTAL", 0
LabelT34:
    db "T34 HIDDEN CKSM=$", 0
LabelT35:
    db "T35 SECTOR0 ST =$", 0
LabelEx1:
    db "EX1 BANK $FF DATA:", 0
LabelEx2:
    db "EX2 C6ROMFLAG =$", 0
HintBackText:
    db "A:BACK TO RESULTS", 0

; --- UI_ResultsLoop ---
; Cycles through the results grid, failure detail, and INFO pages on
; each A-button press (edge-triggered), forever. Call once after the
; full test batch (and, in a destructive build, after the destructive
; batch) has finished.
DEF PAGE_RESULTS EQU 0
DEF PAGE_FAILURE EQU 1
DEF PAGE_INFO EQU 2
DEF PAGE_COUNT EQU 3

EXPORT UI_ResultsLoop
UI_ResultsLoop:
    xor a
    ld [wCurrentPage], a
    ; Seed wPrevJoypad from a real read, not 0 — if the player is still
    ; physically holding A on entry (quite likely right after holding
    ; A+B+START to confirm a destructive run), comparing against a
    ; fake "nothing held" baseline would misread that as a fresh press
    ; and skip a page immediately.
    call ReadJoypad
    ld [wPrevJoypad], a
.showPage:
    ld a, [wCurrentPage]
    cp PAGE_RESULTS
    jr nz, .checkFailure
    call DrawResultsGrid
    jr .waitInput
.checkFailure:
    cp PAGE_FAILURE
    jr nz, .showInfoPage
    call DrawFailurePage
    jr .waitInput
.showInfoPage:
    call DrawInfoPage
.waitInput:
    call WaitFrame
    call ReadJoypad
    ld c, a
    ld a, [wPrevJoypad]
    ld b, a
    ld a, c
    ld [wPrevJoypad], a
    and JOY_A
    jr z, .waitInput
    ld a, b
    and JOY_A
    jr nz, .waitInput        ; already held last frame: not a fresh press
    ld a, [wCurrentPage]
    inc a
    cp PAGE_COUNT
    jr nz, .storePage
    xor a
.storePage:
    ld [wCurrentPage], a
    jr .showPage

; --- UI_ShowCgbRequired ---
; Displayed instead of test results when DetectCGBCapability failed.
EXPORT UI_ShowCgbRequired
UI_ShowCgbRequired:
    call UI_Init
    ld hl, CgbRequiredText
    ld de, _SCRN0 + 3 * SCRN_WIDTH + 3
    call PrintString
    call UI_TurnOn
    ret

CgbRequiredText:
    db "CGB REQUIRED", 0

; ==========================================================================
; Destructive-mode confirmation UI. Only assembled into
; ENABLE_DESTRUCTIVE_FLASH_TESTS=1 builds (CLAUDE.md: "require
; deliberate multi-button confirmation before the first destructive
; operation").
; ==========================================================================
IF DEF(ENABLE_DESTRUCTIVE_FLASH_TESTS) && ENABLE_DESTRUCTIVE_FLASH_TESTS

DEF JOY_CONFIRM_MASK EQU JOY_A | JOY_B | JOY_START

; Roughly 2 seconds at 60 fps, paced by WaitFrame.
DEF CONFIRM_HOLD_FRAMES EQU 120

; --- UI_ConfirmDestructive ---
; Shows a warning and requires holding A+B+START together for
; CONFIRM_HOLD_FRAMES consecutive frames. SELECT alone cancels.
; Output: carry clear if confirmed, carry set if cancelled.
EXPORT UI_ConfirmDestructive
UI_ConfirmDestructive:
    call UI_Init
    ld hl, WarnText1
    ld de, _SCRN0 + 1 * SCRN_WIDTH + 0
    call PrintString
    ld hl, WarnText2
    ld de, _SCRN0 + 3 * SCRN_WIDTH + 0
    call PrintString
    ld hl, WarnText3
    ld de, _SCRN0 + 5 * SCRN_WIDTH + 0
    call PrintString
    ld hl, WarnText4
    ld de, _SCRN0 + 7 * SCRN_WIDTH + 0
    call PrintString
    ld hl, WarnText5
    ld de, _SCRN0 + 9 * SCRN_WIDTH + 0
    call PrintString
    call UI_TurnOn

    ld b, 0            ; consecutive-hold frame counter
.pollLoop:
    call WaitFrame
    call ReadJoypad
    ld c, a
    and JOY_CONFIRM_MASK
    cp JOY_CONFIRM_MASK
    jr nz, .notHeld
    inc b
    ld a, b
    cp CONFIRM_HOLD_FRAMES
    jr nc, .confirmed
    jr .pollLoop
.notHeld:
    ld b, 0
    ld a, c
    and JOY_SELECT
    jr nz, .cancelled
    jr .pollLoop
.confirmed:
    or a
    ret
.cancelled:
    scf
    ret

WarnText1:
    db "DESTRUCTIVE TESTS", 0
WarnText2:
    db "MAY PERMANENTLY", 0
WarnText3:
    db "ERASE CART FLASH", 0
WarnText4:
    db "HOLD A+B+START", 0
WarnText5:
    db "SELECT=CANCEL", 0

ENDC
