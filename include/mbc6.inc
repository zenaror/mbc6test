; MBC6 mapper register map and memory windows.
; Source: CLAUDE.md "MBC6 memory model" (project-authoritative summary
; of Pan Docs MBC6 — https://gbdev.io/pandocs/MBC6.html).
;
; MBC6 ROM/Flash bank numbers are 8 KiB units. MBC6 SRAM bank numbers
; are 4 KiB units. Bank 0 is valid in the switchable ROM windows.

; ---- CPU-visible memory windows ----
DEF MBC6_ROM_FIXED_START EQU $0000
DEF MBC6_ROM_FIXED_END EQU $3FFF
DEF MBC6_ROM_WIN_A EQU $4000  ; $4000-$5FFF, 8 KiB
DEF MBC6_ROM_WIN_B EQU $6000  ; $6000-$7FFF, 8 KiB
DEF MBC6_SRAM_WIN_A EQU $A000  ; $A000-$AFFF, 4 KiB
DEF MBC6_SRAM_WIN_B EQU $B000  ; $B000-$BFFF, 4 KiB

DEF MBC6_ROM_WINDOW_SIZE EQU $2000
DEF MBC6_SRAM_WINDOW_SIZE EQU $1000

; Physical 8 KiB bank signature location within each window (see
; tools/mbc6_layout.py SIG_LOCAL_OFFSET) — reused by both the ROM
; banking tests and the flash tests (T30's window-content checks).
DEF WIN_A_SIG EQU MBC6_ROM_WIN_A + $1FF0 ; $5FF0
DEF WIN_B_SIG EQU MBC6_ROM_WIN_B + $1FF0 ; $7FF0

; ---- Mapper registers (all writes must originate from fixed ROM) ----
DEF MBC6_REG_SRAM_ENABLE EQU $0000 ; $0000-$03FF
DEF MBC6_REG_SRAM_BANK_A EQU $0400 ; $0400-$07FF
DEF MBC6_REG_SRAM_BANK_B EQU $0800 ; $0800-$0BFF
DEF MBC6_REG_FLASH_ENABLE EQU $0C00 ; $0C00-$0FFF
DEF MBC6_REG_FLASH_WE EQU $1000 ; Flash Write Enable / WP control
DEF MBC6_REG_ROM_BANK_A EQU $2000 ; $2000-$27FF
DEF MBC6_REG_ROM_SRC_A EQU $2800 ; $2800-$2FFF ($00 ROM, $08 flash)
DEF MBC6_REG_ROM_BANK_B EQU $3000 ; $3000-$37FF
DEF MBC6_REG_ROM_SRC_B EQU $3800 ; $3800-$3FFF ($00 ROM, $08 flash)

DEF MBC6_SRAM_ENABLE_VALUE EQU $0A
DEF MBC6_SRAM_DISABLE_VALUE EQU $00

DEF MBC6_SRC_ROM EQU $00
DEF MBC6_SRC_FLASH EQU $08

DEF MBC6_FLASH_ENABLE_VALUE EQU $01
DEF MBC6_FLASH_DISABLE_VALUE EQU $00

; ---- Bank counts ----
DEF MBC6_ROM_BANK_COUNT EQU 128 ; 8 KiB units, $00-$7F, for a 1 MiB image
DEF MBC6_SRAM_BANK_COUNT EQU 8   ; 4 KiB units, $00-$07, for 32 KiB SRAM

; ---- Documented power-on state (iceboy MBC6 pseudocode) ----
DEF MBC6_POWERON_SRAM_BANK_A EQU 0
DEF MBC6_POWERON_SRAM_BANK_B EQU 1
DEF MBC6_POWERON_ROM_BANK_A EQU 2
DEF MBC6_POWERON_ROM_BANK_B EQU 3

; ---- Flash (Macronix MX29F008TC-14) ----
DEF FLASH_JEDEC_MANUFACTURER EQU $C2 ; Net de Get
DEF FLASH_JEDEC_DEVICE EQU $81
DEF FLASH_SECTOR_SIZE EQU $20000 ; 128 KiB
DEF FLASH_SECTOR_COUNT EQU 8
DEF FLASH_HIDDEN_REGION_SIZE EQU 256
DEF FLASH_STATUS_READY_BIT EQU 7
DEF FLASH_STATUS_TIMEOUT_BIT EQU 4
DEF FLASH_CMD_RESET EQU $F0

; Software timeout for status-polling loops (destructive tests only).
; CLAUDE.md: "Any flash status polling loop must have a software
; timeout." Not tuned against real hardware timing — chosen generously
; large so a working implementation always finishes well within it.
DEF FLASH_TIMEOUT_ITERATIONS EQU 60000

; Sector geometry: 128 KiB sectors, 16 physical 8 KiB banks each.
DEF FLASH_BANKS_PER_SECTOR EQU 16
DEF FLASH_SECTOR7_FIRST_BANK EQU 112 ; 7 * 16

; ---- Flash command interface (iceboy np_gb_memory.html) ----
; Logical JEDEC command addresses $5555/$2AAA are reached by mapping
; ROM Bank A = 2 (so CPU $5555, inside window A, equals flash linear
; address $05555) and ROM Bank B = 1 (so CPU $6AAA, inside window B,
; equals flash linear address $02AAA) — both windows selecting flash
; as their source. This specific bank pair is what makes the two
; command addresses simultaneously reachable without a bank switch
; mid-sequence.
DEF FLASH_CMD_BANK_A EQU 2
DEF FLASH_CMD_BANK_B EQU 1
DEF FLASH_CMD_ADDR_A EQU $5555
DEF FLASH_CMD_ADDR_B EQU $6AAA

DEF FLASH_CMD_UNLOCK1     EQU $AA
DEF FLASH_CMD_UNLOCK2     EQU $55
DEF FLASH_CMD_AUTOSELECT  EQU $90
DEF FLASH_CMD_HIDDEN_MODE EQU $77
