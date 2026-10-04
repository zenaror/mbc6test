; Experimental / observational tests: EX01, EX02.
;
; docs/project-rules.md "Undefined / experimental behavior": the historical GBDev
; MBC6 research thread (project reference #2) mentions two behaviors
; that are not confirmed by current Pan Docs or the iceboy flash
; documentation. These are recorded as INFO only, never PASS/FAIL, and
; never contribute to the compatibility score — see RecordResult's
; INFO path in src/test_common.asm.

INCLUDE "hardware.inc"
INCLUDE "mbc6.inc"
INCLUDE "tests.inc"

SECTION "Experimental WRAM", WRAM0
wEx01Observed:: ds 16
wEx02Observed:: db

SECTION "Experimental Tests", ROM0

; --- Test_EX01 --- high bank-number bit observation.
; The research thread describes a high bank-number bit apparently
; unmapping ROM in some (unspecified) circumstances. Physical ROM
; banks only span $00-$7F (7 bits); this selects bank $FF (bit 7 set,
; well outside the documented range) in window A and records whatever
; 16 bytes come back at the signature offset, with no expected value
; — purely diagnostic. Never treat this as a required behavior.
EXPORT Test_EX01
Test_EX01:
    call MBC6_SelectROMA
    ld a, $FF
    call MBC6_SetROMBankA
    ld hl, WIN_A_SIG
    ld de, wEx01Observed
    ld b, 16
.copy:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .copy
    ld a, T_EX01
    ld d, RESULT_INFO
    call RecordResult
    ret

; --- Test_EX02 --- $C6 bank-type/source write observation.
; The research thread notes Net de Get writes $C6 to a bank
; source/type register ($2800-$2FFF / $3800-$3FFF, which per current
; Pan Docs only document $00 = ROM and $08 = flash) for an unknown
; reason. This writes $C6 to the Bank A source register and then
; records which source appears to be active by comparing window A's
; content against the expected ROM signature for the bank already
; selected — a match suggests $C6 behaved like "ROM" ($00), a mismatch
; suggests something else. Either outcome is recorded as INFO only.
EXPORT Test_EX02
Test_EX02:
    call MBC6_SelectROMA
    ld a, 5
    call MBC6_SetROMBankA
    ld a, $C6
    ld [MBC6_REG_ROM_SRC_A], a
    ld a, 5
    ld de, WIN_A_SIG
    call CheckBankSignatureAt
    ld a, 0
    jr nc, .looksLikeRom
    ld a, 1
.looksLikeRom:
    ld [wEx02Observed], a ; 0 = matched ROM bank 5 signature, 1 = did not
    call MBC6_SelectROMA  ; restore documented ROM source before continuing
    ld a, T_EX02
    ld d, RESULT_INFO
    call RecordResult
    ret
