# Test matrix

Authoritative source precedence follows `docs/project-rules.md`: current Pan Docs
first, then the iceboy flash documentation, then the GBDev MBC6
research thread, then the MBC3/MBC30 test ROMs (design inspiration
only). "Implementation status" reflects this repository's source, not
any particular emulator's behavior.

| ID | Name | Class | Behavior tested | Authoritative source | Expected result | Status |
|----|------|-------|------------------|----------------------|------------------|--------|
| T00 | Startup/header sanity | Safe | Displays ROM/test-suite version; no runtime expectation | N/A (build-time verifier is authoritative for header bytes) | INFO always | Implemented |
| T01 | Power-on mapper state capture | Safe | Switchable ROM windows resolve to physical banks 2 (A) / 3 (B) before any MBC6 register write | iceboy MBC6 power-on pseudocode; docs/project-rules.md "Power-on state" | PASS if windows show banks 2/3 pre-write | Implemented |
| T10 | ROM Bank A full sweep | Safe | Bank A shows the correct physical 8 KiB bank for all values $00-$7F | Pan Docs MBC6; docs/project-rules.md "ROM bank layout" | PASS all 128 banks match | Implemented |
| T11 | ROM Bank B full sweep | Safe | Same as T10, through window B | Pan Docs MBC6 | PASS all 128 banks match | Implemented |
| T12 | ROM Bank A/B independence | Safe | Changing one window's bank does not affect the other, across 6 pairs incl. edge/cross cases | docs/project-rules.md T12 pair list | PASS | Implemented |
| T13 | ROM bank 0 mapping | Safe | Physical bank 0 is a legal, distinct selection in both switchable windows | Pan Docs MBC6 ("Bank 0 is valid in the switchable ROM windows") | PASS | Implemented |
| T14 | ROM window boundaries | Safe | Windows resolve to commanded banks at extremes ($7F/$00 and swapped); fixed ROM (banks 0/1) unaffected by window changes | Pan Docs MBC6 memory map | PASS | Implemented |
| T20 | SRAM disabled behavior | Safe | A write issued while SRAM is disabled does not persist | Pan Docs (general MBC RAM-enable semantics) | PASS | Implemented |
| T21 | SRAM Bank A sweep | Safe | Banks 0-7 hold distinct, persistent data at 2 offsets each through window A | Pan Docs MBC6; docs/project-rules.md "SRAM testing" | PASS | Implemented |
| T22 | SRAM Bank B sweep | Safe | Same as T21, through window B | Pan Docs MBC6 | PASS | Implemented |
| T23 | SRAM A/B independence | Safe | Changing one SRAM window's bank does not affect the other | Pan Docs MBC6; docs/project-rules.md | PASS | Implemented |
| T24 | SRAM 4 KiB granularity | Safe | Adjacent bank pairs (0/1, 3/4, 6/7) are independently addressable, not 8 KiB-aliased | docs/project-rules.md "MBC6 SRAM bank numbers are 4 KiB units" | PASS | Implemented |
| T30 | ROM/Flash source selection isolation | Safe | Toggling one window's ROM/Flash source does not disturb the other window's source or bank number | docs/project-rules.md "independent ROM-vs-flash source selection" | PASS | Implemented |
| T31 | Flash JEDEC ID through Bank A | Safe | Autoselect sequence + read returns manufacturer $C2 / device $81 | iceboy Nintendo Power GB Memory doc | PASS | Implemented — FAILs on GBE+ and mGBA (see `docs/mbc6-notes.md`; both emulators leave flash ID readback unimplemented) |
| T32 | Flash JEDEC ID through Bank B | Safe | Same as T31, through window B | iceboy Nintendo Power GB Memory doc | PASS | Implemented — same emulator-gap caveat as T31 |
| T33 | Flash reset command | Safe | `$F0` exits ID mode; a differential check (ID bytes no longer read back) | iceboy Nintendo Power GB Memory doc | PASS | Implemented — same emulator-gap caveat |
| T34 | Hidden 256-byte region read mode | Safe | Enter hidden-map mode, checksum 256 bytes, exit | iceboy Nintendo Power GB Memory doc | INFO (no normative payload) | Implemented |
| T35 | Sector-0 protection observation | Safe | Records the as-observed byte at the flash window with no operation in progress | iceboy Nintendo Power GB Memory doc (status bit 1 meaning is documented only in-operation; validity outside an operation is unconfirmed) | INFO | Implemented |
| EX01 | High bank-number bit observation | Safe, experimental | Selects ROM bank $FF (bit 7 set, outside the documented $00-$7F range) and records the 16 observed bytes | GBDev MBC6 research thread (unresolved observation) | INFO only, never PASS/FAIL | Implemented |
| EX02 | `$C6` bank-type write observation | Safe, experimental | Writes `$C6` to the Bank A source register and records whether window A still reads as the ROM bank already selected | GBDev MBC6 research thread (unresolved observation) | INFO only, never PASS/FAIL | Implemented |
| TD1 | Sector erase (sector 7 by convention) | Destructive | Erase, poll status, reset, verify all `$FF` | iceboy Nintendo Power GB Memory doc | PASS, bounded by timeout | Implemented, disabled by default |
| TD2 | 128-byte buffered programming | Destructive | Buffered write procedure, status poll, reset, readback | iceboy Nintendo Power GB Memory doc | PASS, bounded by timeout | Implemented, disabled by default |
| TD3 | 1→0 programming semantics | Destructive | Programming only clears bits, never sets them without an erase | iceboy Nintendo Power GB Memory doc (NOR flash semantics) | PASS | Implemented, disabled by default |
| TD4 | Flash status bits | Destructive | Completion (bit 7) and timeout (bit 4) detected without an infinite loop | iceboy Nintendo Power GB Memory doc | PASS, bounded by timeout | Implemented, disabled by default |
| TD5 | Sector-0 WP behavior | Destructive | Sector-0/hidden-region write protection mechanism, disposable-flash-only | iceboy Nintendo Power GB Memory doc | INFO/PASS per observed behavior | Implemented, disabled by default |
| TD6 | Hidden-region erase/program | Destructive, optional/advanced | Same safeguards as TD1/TD2, applied to the hidden region | iceboy Nintendo Power GB Memory doc | PASS, bounded by timeout | Implemented, disabled by default |

## Notes

- "Implemented, disabled by default" means the code exists in
  `src/tests_flash_destructive.asm` but is compiled out unless built
  with `ENABLE_DESTRUCTIVE_FLASH_TESTS=1` (see `docs/project-rules.md` "Destructive
  flash policy") — the default build cannot reach any of TD1-TD6.
- T31-T33's emulator-observed FAILs are a documented, expected
  consequence of incomplete MBC6 flash emulation in the two engines
  tested so far, not evidence of an error in this ROM's test logic —
  see `docs/mbc6-notes.md` for the source-level root cause in each
  emulator.
- INFO results never contribute to the PASS/FAIL compatibility score
  (`RecordResult` in `src/test_common.asm`).
