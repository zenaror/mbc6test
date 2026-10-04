# Reading the screen

This is the legend for what the ROM shows on real hardware or in an
emulator — written so a human looking at the screen (or a photo/video
of it) can understand a result without reading any source code or
`docs/test-matrix.md`, the same way a SNES burn-in cartridge or
`mbc30test` prints a self-explanatory grid instead of one generic
pass/fail light. `docs/test-matrix.md` is still the authoritative
per-test reference (source citations, exact expected values); this
page is the on-screen companion to it.

## Screens

The ROM shows one of these on boot:

1. **`CGB REQUIRED`** — the ROM detected it isn't running on CGB
   hardware/in CGB mode (see `README.md`). No test ran. Not a MBC6
   result of any kind.
2. **Destructive confirmation warning** (only in a build compiled
   with `ENABLE_DESTRUCTIVE_FLASH_TESTS=1` — never present in a
   default build). Hold **A+B+START** together for about 2 seconds to
   proceed, or press **SELECT** to skip straight to the results below
   without running TD1-TD6.
3. **Results** (always shown once the safe test batch finishes). Three
   pages, cycled by pressing **A**:
   - **`MBC6 TEST RESULTS`** — every test's ID and status.
   - **`FAILURE DETAIL`** — the first FAIL this run, in full.
   - **`INFO / EXPERIMENTAL`** — diagnostic values with no pass/fail
     meaning.

   Pressing A on the INFO page wraps back to the results page.

Every screen also shows a build line in the bottom-left corner, e.g.
`B:95ECD80` — the 7-character short git commit hash the ROM was built
from (`+` appended if built from an uncommitted/dirty tree). Include
this in any bug report; see `README.md` "Identifying a build".

## Status letters

Each test on the results page shows one letter:

| Letter | Meaning |
|--------|---------|
| `P` | PASS — documented required behavior matched. |
| `F` | FAIL — documented required behavior did not match. Look at the FAILURE DETAIL page (the first FAIL each run; if more than one test failed, only the first one's detail is shown — check `docs/test-matrix.md` for what the others test). |
| `S` | SKIP — this test couldn't run safely/meaningfully right now. |
| `I` | INFO — an observation with no right/wrong answer. Never counts toward the summary's pass/fail meaning. |
| `-` | Didn't run at all in this build (e.g. every `TD` test in a default, non-destructive build). Not the same as PASS, even though PASS is internally the number 0 — this is why `-` exists as its own symbol. |

The summary line (`P:.. F:.. S:.. I:..`) at the bottom of the results
page just totals those letters.

**Bottom line: `F` anywhere means something is wrong, unless
`docs/test-matrix.md` specifically says that test is known to fail
against the emulator you're using** (as of this writing, T31/T32/T33
are documented, expected FAILs on GBE+ and mGBA specifically — see
`docs/mbc6-notes.md` — because those two emulators don't implement
flash JEDEC ID readback, not because this ROM is wrong).

## Test ID legend

Three-letter code shown on screen → what it actually tests. Full
detail (authoritative source, exact expected value) is in
`docs/test-matrix.md`; this is the short human-readable version.

| Code | What it tests |
|------|----------------|
| `T00` | Startup/header info. Always `I` — diagnostic only. |
| `T01` | Power-on state: before touching any MBC6 register, the ROM windows already show banks 2 and 3, as documented. |
| `T10` | Bank A window ($4000-$5FFF) can show every one of the 128 physical ROM banks. |
| `T11` | Same as T10, for Bank B window ($6000-$7FFF). |
| `T12` | Changing Bank A's selection never affects Bank B's, and vice versa. |
| `T13` | Physical bank 0 can be explicitly selected in either window (unlike most other mappers, where bank 0 is off-limits there). |
| `T14` | The two ROM windows stay inside their boundaries — no bleed into each other or into fixed ROM. |
| `T20` | A write made while SRAM is disabled doesn't stick. |
| `T21` | SRAM window A ($A000-$AFFF) can show all 8 SRAM banks, each holding distinct data. |
| `T22` | Same as T21, for SRAM window B ($B000-$BFFF). |
| `T23` | SRAM window A and B bank selections are independent. |
| `T24` | SRAM banks are 4 KiB apart, not 8 KiB — adjacent banks don't alias. |
| `T30` | Switching one ROM window between "ROM" and "Flash" source doesn't disturb the other window. |
| `T31` | Reading the flash chip's manufacturer/device ID ($C2/$81) through window A. |
| `T32` | Same as T31, through window B. |
| `T33` | The flash reset command ($F0) actually exits ID mode. |
| `T34` | Reads the flash chip's hidden 256-byte region and reports a checksum. Always `I` — there's no known-correct content to compare against. |
| `T35` | Observes (doesn't modify) whatever byte the flash status line shows for sector 0 outside of an active operation. Always `I` — not confirmed meaningful outside an erase/program in progress. |
| `EX1` | Experimental: what happens selecting ROM bank $FF (an out-of-range bank number with a high bit set). Always `I` — no documented expected behavior. |
| `EX2` | Experimental: what happens writing the undocumented value `$C6` to a bank-source register. Always `I`. |
| `TD1` | *(destructive only)* Erases flash sector 7 and confirms it reads back as `$FF`. |
| `TD2` | *(destructive only)* Programs a 128-byte block and reads it back. |
| `TD3` | *(destructive only)* Confirms programming can only clear bits (1→0), never set them back to 1 without an erase. |
| `TD4` | *(destructive only)* Confirms the flash status "done" bit is reported and the polling timeout mechanism works. |
| `TD5` | *(destructive only)* Observes sector-0 write-protect behavior. Always `I`. |
| `TD6` | *(destructive only)* Always `S` — no authoritative source documents a hidden-region erase/program sequence, so this is honestly skipped rather than guessed at. |

## The FAILURE DETAIL page

```
FAILURE DETAIL

TEST ID = $0D
BANK    = $00
ADDRESS = $4000
EXPECTED= $C2
ACTUAL  = $FF
```

- **TEST ID** — hex value of the failing test. Convert with the table
  in `include/tests.inc` or `docs/test-matrix.md` (e.g. `$0D` = 13
  decimal = `T31`).
- **BANK** — which ROM/SRAM/flash bank number was selected when the
  mismatch happened. Meaning depends on the test (e.g. for a JEDEC ID
  test this is diagnostic, not a real bank).
- **ADDRESS** — the full 16-bit CPU address that was read.
- **EXPECTED** / **ACTUAL** — the byte that should have been there,
  and the byte that actually was, both in hex.

If the page instead says **`NO FAILURES`**, no test failed this run.

## The INFO / EXPERIMENTAL page

```
INFO / EXPERIMENTAL

T34 HIDDEN CKSM=$00
T35 SECTOR0 ST =$FF
EX1 BANK $FF DATA:
4D 36 42 4B
EX2 C6ROMFLAG =$00
```

- **T34 HIDDEN CKSM** — an XOR checksum of the 256-byte hidden flash
  region. No expected value; useful for noticing if it *changes*
  between runs/implementations, not for judging correct vs. incorrect.
- **T35 SECTOR0 ST** — the raw byte observed at the flash status
  address for sector 0, outside of any erase/program operation.
- **EX1 BANK $FF DATA** — the first 4 of the 16 bytes read back when
  ROM bank `$FF` (invalid/out-of-range) is selected. `4D 36 42 4B`
  ("M6BK" in ASCII) is the magic that starts *every* bank's signature,
  so it only shows that some valid ROM bank is still mapped (ROM did
  not become unreadable) — not which bank. The bank number is the 5th
  signature byte, which this page doesn't show. In GBE+ and mGBA, the
  code maps bank `$FF` to bank `$7F` (GBE+ masks the high bit; mGBA
  wraps by ROM size); what real hardware does is unknown — the GBDev
  research thread reported the high bit appearing to unmap ROM.
- **EX2 C6ROMFLAG** — `$00` if window A still read like ordinary ROM
  after writing the undocumented value `$C6` to its source-select
  register; `$01` if it read like something else.

## Machine-readable results

If you have a way to inspect SRAM (a savestate, a memory viewer, a
script), `docs/result-format.md` documents a 20-byte struct at SRAM
bank 7 / window B offset `$F00` with the same information as the
results page in binary form — useful for scripted verification
instead of reading the screen.
