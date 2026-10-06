# Machine-readable result block

Optional, for emulator CI automation (original project prompt §15; see
also `docs/project-rules.md` "SRAM testing"). Written once, at
the very end of the safe test batch, **after** T20-T24 (the SRAM
banking tests) have already run and recorded their own PASS/FAIL —
so this block never influences, and is never influenced by, those
tests' own read/write patterns.

## Location

The opt-in offline workflow has a separate 32-byte `M6OF` annex at `$BF20`.
It does not overlap this 21-byte `M6TS` block or extend its test IDs/bitset.
In that build, M6TS describes the safe suite; read M6OF for the offline verdict.
See [net-de-get-offline.md](net-de-get-offline.md) for the annex ABI.

- **SRAM bank:** 7 (last bank), selected in **window B**
  (`MBC6_REG_SRAM_BANK_B`).
- **Offset:** `$F00` within the 4 KiB window (`$B000 + $F00 = $BF00`).
- SRAM must be enabled (`$0A` to `MBC6_REG_SRAM_ENABLE`) to read it,
  exactly like any other SRAM access.

This offset is chosen simply to stay clear of the two offsets (`$000`
and `$FFF`) T21-T24 exercise, though since the block is written last,
any overlap would only ever show the final block contents, not corrupt
an in-progress test.

## Layout (21 bytes, all fixed offsets from the block base)

| Offset | Size | Field | Meaning |
|--------|------|-------|---------|
| 0 | 4 | magic | ASCII `"M6TS"` |
| 4 | 1 | format_version | Layout version of this table; `2` |
| 5 | 1 | suite_version | Test-suite version; `3` |
| 6 | 1 | pass_count | Total PASS results |
| 7 | 1 | fail_count | Total FAIL results |
| 8 | 1 | skip_count | Total SKIP results |
| 9 | 1 | info_count | Total INFO results |
| 10 | 4 | failed_bitset | Bit `i` of byte `i/8` (LSB-first within each byte) set if test ID `i` FAILed. Covers test IDs 0-31; see `include/tests.inc` for the current ID assignment. |
| 14 | 1 | first_fail_test_id | Test ID of the first FAIL this run, or `$FF` if none |
| 15 | 1 | first_fail_bank | Bank number associated with the first failure |
| 16 | 1 | first_fail_addr_hi | High byte of the address associated with the first failure |
| 17 | 1 | first_fail_addr_lo | Low byte of the address associated with the first failure |
| 18 | 1 | first_fail_expected | Expected byte at the first failure |
| 19 | 1 | first_fail_actual | Actual byte at the first failure |
| 20 | 1 | checksum | Sum of bytes 0-19, mod 256 |

If `fail_count` is 0, `first_fail_*` fields are all `$00` and
`first_fail_test_id` is `$FF` (no failure).

## Reading it from a savestate/memory dump

1. Ensure SRAM is enabled and bank 7 is selected in window B (or read
   it via whatever your tool's raw SRAM-file view offers — the offset
   within the 32 KiB SRAM image is `7 * $1000 + $F00 = $7F00`).
2. Verify the magic and checksum before trusting the rest.
3. `failed_bitset` plus `include/tests.inc` gives the full list of
   failed test IDs without needing to screen-scrape the UI.

## Implementation

See `WriteResultBlock` in `src/test_common.asm`, called once from
`src/main.asm` after the full safe test batch (including EX01/EX02)
completes.
