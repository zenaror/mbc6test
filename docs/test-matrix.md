# Test matrix

Authoritative source precedence follows [project-rules.md](project-rules.md):
current Pan Docs, an exact-part manufacturer datasheet if available, then
cartridge-specific Iceboy research and GBDev observations. The linked
MX29F800C datasheet describes a related part. MBC3/MBC30 test ROMs are design
inspiration only. "Implementation status" reflects this repository's source;
dated emulator results are recorded separately in [mbc6-notes.md](mbc6-notes.md).
The reusable protocol reference and integrated offline coverage are in
[mbc6-reference.md](mbc6-reference.md).

The separate [offline workflow fixture](net-de-get-offline.md) tests WRAM
staging, 64 page writes, full readback/sums, payload execution and restoration;
its host runner checks fresh-core persistence and negative cases. It is selected
with `ENABLE_NETDEGET_OFFLINE_FIXTURE=1` in addition to both destructive flags
and replaces TD1-TD12. It has its own M6OF annex, not a new M6TS test ID.

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
| T30 | ROM/Flash source-latch isolation | Safe | Toggles A to flash and checks B's ROM signature before touching B; then toggles B and checks A's ROM signature; restores each and checks its bank retention | Pan Docs MBC6 independent ROM-vs-flash source selection | PASS if each untouched window retains its 16-byte ROM signature; theoretical false match if flash has the exact signature at that location | Implemented; checks both directions without depending on flash contents |
| T31 | Flash JEDEC ID through Bank A | Safe | Autoselect sequence + read returns manufacturer $C2 / device $81 | iceboy Nintendo Power GB Memory doc | PASS | Implemented; passed in the dated mGBA `4c8066be4` / `358230c82` full-suite runs; older GBE+ gap is recorded in mbc6-notes.md |
| T32 | Flash JEDEC ID through Bank B | Safe | Sends the full unlock/autoselect sequence through window B alone (Bank B 2 → 1 → 2), then reads manufacturer $C2 / device $81 there | iceboy flash command sequence; Pan Docs MBC6 window/bank mapping | PASS | Implemented; same dated mGBA execution evidence as T31 |
| T33 | Flash reset command | Safe | `$F0` exits ID mode; a differential check (ID bytes no longer read back) | iceboy Nintendo Power GB Memory doc | PASS | Implemented; same dated mGBA execution evidence as T31; hardware and upstream releases remain unverified |
| T34 | Hidden 256-byte region read mode | Safe | Enter hidden-map mode, checksum 256 bytes, exit | iceboy Nintendo Power GB Memory doc | INFO (no normative payload) | Implemented |
| T35 | Sector-0 protection status observation | Safe, INFO only | Under flash WP, enters program/status mode with `$AA/$55/$A0`, reads status bit 1 at `$4000`, then calls `Flash_Reset` before loading buffer data or issuing a repeated-slot trigger | Iceboy Net de Get `is_sector0_protected()` procedure; status bit 1 meaning | INFO only; record raw status byte, do not score protection state as PASS/FAIL | Implemented; no persistent flash operation is triggered |
| EX01 | High bank-number bit observation | Safe, experimental | Selects ROM bank $FF (bit 7 set, outside the documented $00-$7F range) and records the 16 observed bytes | GBDev MBC6 research thread (unresolved observation) | INFO only, never PASS/FAIL | Implemented |
| EX02 | `$C6` bank-type write observation | Safe, experimental | Writes `$C6` to the Bank A source register and records whether window A still reads as the ROM bank already selected | GBDev MBC6 research thread (unresolved observation) | INFO only, never PASS/FAIL | Implemented |
| TD1 | Sector erase (sector 7 by convention) | Destructive | Erase, poll status, reset, verify all `$FF` | iceboy Nintendo Power GB Memory doc | PASS, bounded by timeout | Implemented, disabled by default |
| TD2 | 128-byte buffered programming | Destructive | Buffered write procedure, status poll, reset, readback | iceboy Nintendo Power GB Memory doc | PASS, bounded by timeout | Implemented, disabled by default |
| TD3 | 1→0 programming semantics | Destructive | Programming only clears bits, never sets them without an erase | iceboy Nintendo Power GB Memory doc (NOR flash semantics) | PASS | Implemented, disabled by default |
| TD4 | Flash ready and bounded polling | Destructive | Reprograms a fixture page and checks that the ROM's polling routine sees ready bit 7 before its software iteration limit | Iceboy documents ready bit 7; Dan Docs reports Net de Get checks bit 4 as timeout, while Iceboy calls bits 5–4 unknown | PASS for completion before software timeout; does not test status bit 4 | Implemented, disabled by default |
| TD5 | Sector-0 WP behavior | Destructive | Sector-0/hidden-region write protection mechanism, disposable-flash-only | iceboy Nintendo Power GB Memory doc | INFO/PASS per observed behavior | Implemented, disabled by default |
| TD6 | Hidden-map erase/program and write protection | mGBA fixture only | Requires the 16-byte hidden-map marker `M6TD6FIXTUREONLY` at offsets `$F0-$FF`; erases and checks all 256 bytes through A/B, programs `$10`/`$80` into both 128-byte halves, checks ready/reset, then verifies WP blocks erase and program | iceboy Nintendo Power GB Memory doc, Flash commands and Flash program operations | SKIP without marker; otherwise PASS if every byte and bounded ready check matches, FAIL with first mismatch | Implemented behind both destructive and mGBA fixture gates |
| TD7 | Partial/out-of-order page buffer and trigger destination | Destructive, fixture only | Loads slots 5 then 1 into an incomplete buffer in bank 112; repeats the last slot (slot 1) at the mapped address in bank 113 to trigger; verifies both bytes at the trigger destination | Iceboy Nintendo Power GB Memory doc, buffered-write procedure | PASS if completion is bounded and bytes land in bank 113 at the trigger-selected offsets | Implemented, disabled by default |
| TD8 | `$F0` payload vs buffer abort | Destructive, fixture only | Programs `$F0` as a non-trigger payload byte, then repeats another slot with non-`$F0` to commit; separately repeats a slot with `$F0` to abort and verifies the array remains erased | Iceboy Nintendo Power GB Memory doc, buffered-write abort procedure | PASS if payload `$F0` is stored and abort leaves array unchanged | Implemented, disabled by default |
| TD9 | Hidden-map reads through A/B after erase and `$F0` | Destructive fixture observation | Completes a sector-7 erase/reset, enters hidden-map mode, records XOR checksums of the same 256 local offsets via A and B | Pan Docs hidden-map read mode; Dan Docs MBC6 flash-I/O latch is reverse-engineering evidence | INFO only; pair is shown for comparison, equality is not a hardware assertion | Implemented as INFO, disabled by default |
| TD10 | JEDEC ID entry/read across opposite windows | mGBA fixture observation | Enters ID mode with the A sequence and reads from B, then enters via B and reads from A; stores both manufacturer/device pairs | Iceboy documents `$C2/$81` ID bytes and the command sequences; cross-window visibility is observed, not specified as a requirement | INFO only | Implemented behind both destructive and fixture gates |
| TD11 | Buffered-program and chip-erase status through A/B | mGBA fixture observation; chip erase | Samples status immediately through A and B after buffered programming and whole-chip erase; polls to completion, records A/B ready bytes, then resets | Iceboy documents buffered programming and ready bit 7; Dan Docs reports Net de Get checks bit 4 as timeout while Iceboy calls bits 5–4 unknown; iceboy documents Net de Get mass erase `$80/$10`; no exact-part Macronix datasheet was located; cross-window status/timing remains observational | INFO only | Implemented behind both destructive and fixture gates |
| TD12 | Buffer slots 0/127 at first/last 128-byte pages | mGBA fixture observation | Erases sector 7, writes slots 0 and 127 in page `$0000` and last page `$1F80`, repeats slot 127 as trigger, records all four edge bytes | Iceboy's buffered-write procedure documents aligned 128-byte pages and trigger semantics; exact bank-edge behavior remains observational | INFO only | Implemented behind both destructive and fixture gates |

## Notes

- TD1-TD5 and TD7-TD9 are compiled out unless built with
  `ENABLE_DESTRUCTIVE_FLASH_TESTS=1`; TD6 and TD10-TD12 also require
  `ENABLE_MGBA_FLASH_FIXTURE_TESTS=1`. The latter includes a whole-chip erase
  and is only for disposable mGBA ROM/save fixtures (see `docs/project-rules.md`).
- Earlier mGBA T31-T33 results used the local uncommitted `feature/full_server`
  tree. Later full-suite runs on commits `4c8066be4` and `358230c82` also passed
  those tests; see the dated entries in `docs/mbc6-notes.md` for exact artifacts
  and provenance. None establishes hardware behavior or an upstream release.
- INFO results never contribute to the PASS/FAIL compatibility score
  (`RecordResult` in `src/test_common.asm`).
- TD6-TD12 are intended for the mGBA emulator fixture only. The ROM's
  destructive confirmation does not make arbitrary physical cartridges
  disposable; do not run these tests on original hardware or valuable flash.
- TD6 checks the marker before issuing any hidden-map command. Seed that exact
  16-byte token only in a fresh, disposable `.sav.flash` under `/tmp` (or an
  equivalent scratch directory). The token is a fixture gate, not a hardware
  detector; never run any fixture build on a physical cartridge.
- Fixture command: `make ENABLE_DESTRUCTIVE_FLASH_TESTS=1 ENABLE_MGBA_FLASH_FIXTURE_TESTS=1`
  followed by `make verify ENABLE_DESTRUCTIVE_FLASH_TESTS=1 ENABLE_MGBA_FLASH_FIXTURE_TESTS=1`.
  Keep the ROM and `.sav.flash` in a disposable directory.
