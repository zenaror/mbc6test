; Entry point and startup sanity checks.
;
; This ROM is CGB-only (header $0143 = $C0). Real CGB-only hardware
; already refuses to boot on DMG/MGB/SGB, but some emulators do not
; enforce that lock, so we perform our own runtime capability check
; before any MBC6 register is touched.
;
; Per CLAUDE.md / the project brief: do not gate on the CPU register A
; boot hand-off value alone, since that is unreliable when an emulator
; skips the boot ROM. Instead probe a CGB-only hardware capability
; (WRAM banking via rSVBK) and use that as the actual PASS/FAIL gate;
; register A is only preserved for diagnostic display (T00).

INCLUDE "hardware.inc"
INCLUDE "mbc6.inc"

SECTION "Start", ROM0

EXPORT Start
Start:
    di
    ld sp, $FFFE

    ; Preserve the boot hand-off register (A) for diagnostics only —
    ; never used as the CGB gate itself (see header comment above).
    ld [wBootRegA], a

    ; T01: capture the switchable ROM windows before writing any MBC6
    ; register (CLAUDE.md "Power-on state"). Must happen before
    ; anything below that could touch a mapper register.
    call CapturePowerOnState

    call DetectCGBCapability
    jr nc, .cgbConfirmed
    ld a, 1
    ld [wCgbRequired], a
    call UI_ShowCgbRequired
    jr .hang

.cgbConfirmed:
    xor a
    ld [wCgbRequired], a

    call ResetTestState
    call Test_T00
    call Test_T01
    call Test_T10
    call Test_T11
    call Test_T12
    call Test_T13
    call Test_T14
    ; T21/T22 must run before T23/T24 — see src/tests_ram.asm header.
    call Test_T20
    call Test_T21
    call Test_T22
    call Test_T23
    call Test_T24
    call Test_T30
    call Test_T31
    call Test_T32
    call Test_T33
    call Test_T34
    call Test_T35
    ; Experimental/observational only — never affect the compatibility
    ; score (CLAUDE.md "Undefined / experimental behavior").
    call Test_EX01
    call Test_EX02

IF DEF(ENABLE_DESTRUCTIVE_FLASH_TESTS) && ENABLE_DESTRUCTIVE_FLASH_TESTS
    ; Never reachable in a default build (Makefile defaults this to 0)
    ; — CLAUDE.md "Destructive flash policy". Requires deliberate
    ; multi-button confirmation before the first destructive operation.
    call UI_ConfirmDestructive
    jr c, .skipDestructive
    call Test_TD1
    call Test_TD2
    call Test_TD3
    call Test_TD4
    call Test_TD5
    call Test_TD6
.skipDestructive:
ENDC

    ; Optional machine-readable result block (docs/result-format.md).
    ; Written last, after every SRAM banking test has already run.
    call WriteResultBlock

    ; Never returns — cycles the results/failure/INFO pages on A presses.
    call UI_ResultsLoop

.hang:
    halt
    nop
    jr .hang

; --- DetectCGBCapability ---
; Probes rSVBK ($FF70, WRAM bank select), a register that only exists
; in CGB mode. On CGB, writing 2-7 and reading back must return the
; same value in bits 0-2 (0/1 both read back as 1). On DMG/MGB the
; register is unmapped, so a round-trip through a non-1 test value
; will not read back correctly. This is independent of any boot-ROM
; hand-off state. Bits 3-7 of rSVBK are unused and may read back as 1
; (Pan Docs documents several CGB I/O registers this way), so the
; readback is masked to bits 0-2 before comparing — an early version
; of this check compared the raw byte and produced a false CGB
; REQUIRED on mGBA, which models those unused bits as 1, while the
; more permissive GBE+ happened not to.
; Returns: carry clear if CGB capability confirmed, carry set if not.
; Clobbers: A.
DetectCGBCapability:
    ld a, 3
    ldh [rSVBK], a
    ldh a, [rSVBK]
    and $07
    cp 3
    jr nz, .notCgb
    ld a, 1
    ldh [rSVBK], a
    ldh a, [rSVBK]
    and $07
    cp 1
    jr nz, .notCgb
    or a ; clear carry
    ret
.notCgb:
    scf
    ret

SECTION "Startup WRAM", WRAM0
wBootRegA:    db
wCgbRequired: db
