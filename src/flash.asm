; Flash command helpers for the MX29F008TC-14 (Net de Get flash).
;
; Command sequences and the MBC6 address translation are sourced from
; the iceboy NP GB Memory documentation (project reference #3), which
; states the flash behavior documented there also applies to Net de
; Get's 29F008TC, with the documented JEDEC device-ID difference
; ($81 instead of $89). See docs/project-rules.md "Flash rules": command sequences
; must be centralized here, not duplicated across test cases.
;
; All routines here run from fixed ROM (they write MBC6 registers).

INCLUDE "hardware.inc"
INCLUDE "mbc6.inc"

SECTION "Flash Helpers", ROM0

; --- Flash_SelectCommandWindows ---
; Maps ROM Bank A = 2 and ROM Bank B = 1, both sourced from flash, and
; enables flash. This is the bank pair that makes CPU $5555 (window A)
; and CPU $6AAA (window B) simultaneously address flash linear
; $05555 and $02AAA — the two bytes every JEDEC-style command in this
; file needs to reach. Must precede any command sequence below.
;
; The Flash Enable sequence below — briefly setting Flash Write Enable
; ($1000) before writing Flash Enable ($0C00), then dropping $1000
; back to 0 — matches the real, hardware-tested sequence in FlashGBX's
; MBC6 driver (github.com/lesserkuma/FlashGBX, Mapper.py class
; DMG_MBC6.EnableFlash), not just docs/project-rules.md's brief register
; descriptions. It's unclear from available sources whether $0C00
; alone would have worked; this follows what's confirmed to work
; against real Net de Get hardware rather than guessing. Destructive
; helpers that actually need to write re-raise $1000 themselves right
; before doing so — see Flash_EraseSector / Flash_ProgramBuffer*.
EXPORT Flash_SelectCommandWindows
Flash_SelectCommandWindows:
    ld a, 1
    ld [MBC6_REG_FLASH_WE], a
    call MBC6_EnableFlash
    xor a
    ld [MBC6_REG_FLASH_WE], a
    ld a, FLASH_CMD_BANK_A
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ld a, FLASH_CMD_BANK_B
    call MBC6_SetROMBankB
    call MBC6_SelectFlashB
    ret

; --- Flash_Reset ---
; Follow the iceboy pseudocode specifically for Net de Get (MBC6):
; enable flash, write $F0 twice to $4000, wait 100 ms, then write $F0
; once more. The source explains that the first two writes exit a
; pending write-buffer load without starting programming; the delayed
; third write handles an erase/program operation that ignored the first
; resets. This is cartridge research, not a Macronix manufacturer
; datasheet. Do not alter this sequence to match an emulator's model.
EXPORT Flash_Reset
Flash_Reset:
    call Flash_SelectCommandWindows
    ld a, FLASH_CMD_RESET
    ld [MBC6_ROM_WIN_A], a
    ld a, FLASH_CMD_RESET
    ld [MBC6_ROM_WIN_A], a
    call Flash_Wait100ms
    ld a, FLASH_CMD_RESET
    ld [MBC6_ROM_WIN_A], a
    ret

; Wait for 1640 DIV increments: 100.1 ms at the CGB normal-speed
; divider rate (16384 Hz). This does not depend on LCD/VBlank state.
Flash_Wait100ms:
    push bc
    push hl
    ld hl, 1640
    ldh a, [rDIV]
    ld c, a
.waitTick:
    ldh a, [rDIV]
    cp c
    jr z, .waitTick
    ld c, a
    dec hl
    ld a, h
    or l
    jr nz, .waitTick
    pop hl
    pop bc
    ret

; --- Flash_EnterIDMode ---
; Issues the 3-write JEDEC autoselect entry sequence
; ($AA -> $5555, $55 -> $2AAA, $90 -> $5555). After this, the
; manufacturer/device ID bytes repeat across the mapped address space
; (iceboy doc). Calls Flash_SelectCommandWindows first.
EXPORT Flash_EnterIDMode
Flash_EnterIDMode:
    call Flash_SelectCommandWindows
    ld a, FLASH_CMD_UNLOCK1
    ld [FLASH_CMD_ADDR_A], a
    ld a, FLASH_CMD_UNLOCK2
    ld [FLASH_CMD_ADDR_B], a
    ld a, FLASH_CMD_AUTOSELECT
    ld [FLASH_CMD_ADDR_A], a
    ret

; --- Flash_EnterIDModeViaBankB ---
; Issues the complete unlock/autoselect sequence through window B alone.
; Bank B=2 maps CPU $7555 to flash address $5555; Bank B=1 maps
; CPU $6AAA to flash address $2AAA. This checks that the flash command
; decoder follows the selected flash bank independently of window A.
EXPORT Flash_EnterIDModeViaBankB
Flash_EnterIDModeViaBankB:
    call Flash_SelectCommandWindows
    ld a, 2
    call MBC6_SetROMBankB
    ld a, FLASH_CMD_UNLOCK1
    ld [MBC6_ROM_WIN_B + $1555], a
    ld a, 1
    call MBC6_SetROMBankB
    ld a, FLASH_CMD_UNLOCK2
    ld [MBC6_ROM_WIN_B + $0AAA], a
    ld a, 2
    call MBC6_SetROMBankB
    ld a, FLASH_CMD_AUTOSELECT
    ld [MBC6_ROM_WIN_B + $1555], a
    ret

; --- Flash_EnterHiddenMode ---
; Issues the doubled 6-write sequence that switches array reads to
; the hidden 256-byte map (iceboy doc: the sequence
; $AA/$55/$77 issued twice). While in this mode, ordinary flash array
; contents are not readable — only the hidden region. Exit with
; Flash_Reset.
EXPORT Flash_EnterHiddenMode
Flash_EnterHiddenMode:
    call Flash_SelectCommandWindows
    ld a, FLASH_CMD_UNLOCK1
    ld [FLASH_CMD_ADDR_A], a
    ld a, FLASH_CMD_UNLOCK2
    ld [FLASH_CMD_ADDR_B], a
    ld a, FLASH_CMD_HIDDEN_MODE
    ld [FLASH_CMD_ADDR_A], a
    ld a, FLASH_CMD_UNLOCK1
    ld [FLASH_CMD_ADDR_A], a
    ld a, FLASH_CMD_UNLOCK2
    ld [FLASH_CMD_ADDR_B], a
    ld a, FLASH_CMD_HIDDEN_MODE
    ld [FLASH_CMD_ADDR_A], a
    ret

; ==========================================================================
; Everything below is only assembled into ENABLE_DESTRUCTIVE_FLASH_TESTS=1
; builds (docs/project-rules.md "Destructive flash policy": default must be OFF, and
; "no code path should issue erase, program, protect, or unprotect
; commands" when it's off). The default Makefile invocation never
; defines this symbol as 1, so none of this exists in a normal build.
; ==========================================================================
IF DEF(ENABLE_DESTRUCTIVE_FLASH_TESTS) && ENABLE_DESTRUCTIVE_FLASH_TESTS

SECTION "Flash Destructive WRAM", WRAM0
wLastFlashStatus:: db

SECTION "Flash Destructive Helpers", ROM0

; --- Flash_PollStatus ---
; Polls the status byte at [hl] (a window address currently sourced
; from flash) until bit 7 (ready) is set, or FLASH_TIMEOUT_ITERATIONS
; is reached (docs/project-rules.md: "Any flash status polling loop must have a
; software timeout. Never hang forever on an incomplete emulator
; implementation.").
; Output: carry clear if ready, carry set on timeout.
; wLastFlashStatus holds the last status byte read either way.
; Clobbers: a, bc.
EXPORT Flash_PollStatus
Flash_PollStatus:
    ld bc, FLASH_TIMEOUT_ITERATIONS
.loop:
    ld a, [hl]
    ld [wLastFlashStatus], a
    bit FLASH_STATUS_READY_BIT, a
    jr nz, .ready
    dec bc
    ld a, b
    or c
    jr nz, .loop
    scf                       ; timeout
    ret
.ready:
    or a                      ; clear carry
    ret

; --- Flash_EraseSector ---
; Input: a = physical 8 KiB bank number of any bank within the target
; sector. Issues the sector-erase sequence
; ($AA/$2AAA=$55/$5555=$80/$AA/$2AAA=$55/target=$30 — iceboy doc),
; polls for completion with a timeout, and resets afterward regardless
; of outcome. Output: carry set on timeout (wLastFlashStatus valid
; either way). The target address for the final $30 write is reached
; through window A with the given bank mapped as flash.
EXPORT Flash_EraseSector
Flash_EraseSector:
    ld [wEraseTargetBank], a
    call Flash_SelectCommandWindows
    ld a, FLASH_CMD_UNLOCK1
    ld [FLASH_CMD_ADDR_A], a
    ld a, FLASH_CMD_UNLOCK2
    ld [FLASH_CMD_ADDR_B], a
    ld a, $80
    ld [FLASH_CMD_ADDR_A], a
    ld a, FLASH_CMD_UNLOCK1
    ld [FLASH_CMD_ADDR_A], a
    ld a, FLASH_CMD_UNLOCK2
    ld [FLASH_CMD_ADDR_B], a
    ; Map the target bank into window A (flash) to issue $30 there.
    ld a, [wEraseTargetBank]
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA
    ; Flash_SelectCommandWindows left $1000 at 0; raise it again right
    ; before the write that actually erases (see its comment — matches
    ; FlashGBX's confirmed-working sequence).
    ld a, 1
    ld [MBC6_REG_FLASH_WE], a
    ld a, $30
    ld [MBC6_ROM_WIN_A], a
    ld hl, MBC6_ROM_WIN_A
    call Flash_PollStatus
    push af
    call Flash_Reset
    pop af
    ret

; --- Flash_ProgramBuffer ---
; Input: a = physical bank number, de = 128-byte-aligned offset within
; the bank's flash window (0-based, e.g. $0000 or $0080).
; Programs 128 deterministic bytes — pattern(i) = (i*3 + $11) & $FF,
; where i is the byte's position 0-127 within the buffer — using the
; buffered-write procedure: unlock, $A0, write each buffer byte
; exactly once, then commit with a literal $00 write to the final
; address (a second, distinct write — not a repeat of that byte's
; real data value). Per Dan/shonumi's Net de Get reverse-engineering
; (https://shonumi.github.io/dandocs.html, "MBC6 Flash Operation"):
; "At the end of each 128 byte section..., it writes a 0x00 at the
; very last byte," and the real data value already stored there is
; preserved — the $00 is purely a commit signal, confirmed against
; GBE+'s implementation (src/dmg/mbc6.cpp: the finish-signal branch
; requires value==0 and returns before the normal array write).
; Always polls with a timeout and resets afterward, regardless of
; outcome.
; Output: carry set on timeout.
EXPORT Flash_ProgramBuffer
Flash_ProgramBuffer:
    ld [wProgramTargetBank], a
    ld a, e
    ld [wProgramOffsetLo], a
    ld a, d
    ld [wProgramOffsetHi], a

    call Flash_SelectCommandWindows
    ld a, FLASH_CMD_UNLOCK1
    ld [FLASH_CMD_ADDR_A], a
    ld a, FLASH_CMD_UNLOCK2
    ld [FLASH_CMD_ADDR_B], a
    ; Flash_SelectCommandWindows left $1000 at 0; raise it again right
    ; before the write command that actually programs (see its comment).
    ld a, 1
    ld [MBC6_REG_FLASH_WE], a
    ld a, $A0
    ld [FLASH_CMD_ADDR_A], a

    ld a, [wProgramTargetBank]
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA

    ld a, [wProgramOffsetLo]
    ld e, a
    ld a, [wProgramOffsetHi]
    ld d, a
    ld hl, MBC6_ROM_WIN_A
    add hl, de

    ld b, 0
.writeLoop:
    ld a, b
    ld c, a
    add a, a
    add a, c        ; a = index*3
    add a, $11
    ld [hl], a
    inc hl
    inc b
    ld a, b
    cp 128
    jr nz, .writeLoop

    dec hl           ; back to the last byte written
    xor a
    ld [hl], a        ; commit: literal $00, distinct from that byte's data

    call Flash_PollStatus
    push af
    call Flash_Reset
    pop af
    ret

; --- Flash_ProgramBufferFill ---
; Same buffered-write procedure as Flash_ProgramBuffer (see its
; comment for the commit-byte citation), but every one of the 128
; bytes is set to a caller-supplied constant instead of the
; deterministic formula. Used by TD3/TD4/TD5, which need to program a
; single known byte rather than the diagnostic pattern.
; Input: a = physical bank number, de = 128-byte-aligned offset,
; c = fill value.
; Output: carry set on timeout.
EXPORT Flash_ProgramBufferFill
Flash_ProgramBufferFill:
    ld [wProgramTargetBank], a
    ld a, e
    ld [wProgramOffsetLo], a
    ld a, d
    ld [wProgramOffsetHi], a
    ld a, c
    ld [wProgramFillValue], a

    call Flash_SelectCommandWindows
    ld a, FLASH_CMD_UNLOCK1
    ld [FLASH_CMD_ADDR_A], a
    ld a, FLASH_CMD_UNLOCK2
    ld [FLASH_CMD_ADDR_B], a
    ; Flash_SelectCommandWindows left $1000 at 0; raise it again right
    ; before the write command that actually programs (see its comment).
    ld a, 1
    ld [MBC6_REG_FLASH_WE], a
    ld a, $A0
    ld [FLASH_CMD_ADDR_A], a

    ld a, [wProgramTargetBank]
    call MBC6_SetROMBankA
    call MBC6_SelectFlashA

    ld a, [wProgramOffsetLo]
    ld e, a
    ld a, [wProgramOffsetHi]
    ld d, a
    ld hl, MBC6_ROM_WIN_A
    add hl, de

    ld b, 0
.writeLoop:
    ld a, [wProgramFillValue]
    ld [hl], a
    inc hl
    inc b
    ld a, b
    cp 128
    jr nz, .writeLoop

    dec hl
    xor a
    ld [hl], a        ; commit: literal $00, distinct from the fill value

    call Flash_PollStatus
    push af
    call Flash_Reset
    pop af
    ret

SECTION "Flash Destructive Helpers WRAM", WRAM0
wEraseTargetBank: db
wProgramTargetBank: db
wProgramOffsetLo: db
wProgramOffsetHi: db
wProgramFillValue: db

ENDC
