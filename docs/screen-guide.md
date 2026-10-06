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

The separate `ENABLE_NETDEGET_OFFLINE_FIXTURE=1` build starts its results on
an additional **`OFFLINE INSTALL`** page: `RESULT` is PASS/FAIL/SKIP/NOT RUN,
`MODE $01/$02` is install/reopen, `PHASE` identifies the current/failing step,
`PAGES $40/$00` means 64 installed pages/none on reopen, and `EXEC $A65A`
is the successful payload receipt. SELECT at confirmation shows NOT RUN,
never a prior PASS. A then cycles through the three usual pages below.
The safe-suite score is independent of the offline verdict. See
[net-de-get-offline.md](net-de-get-offline.md) for phases and guards.

The ROM shows one of these on boot:

1. **`CGB REQUIRED`** — the ROM detected it isn't running on CGB
   hardware/in CGB mode (see `README.md`). No test ran. Not a MBC6
   result of any kind.
2. **Destructive confirmation warning** (only in a build compiled
   with `ENABLE_DESTRUCTIVE_FLASH_TESTS=1` — never present in a
   default build). Hold **A+B+START** together for about 2 seconds to
   proceed, or press **SELECT** to skip straight to the results below
   without running TD1-TD12.
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
| `T35` | Under WP, enters program/status mode, reads protection bit 1, then resets before loading data or triggering programming. Always `I`; no specific protection state is required. |
| `EX1` | Experimental: what happens selecting ROM bank $FF (an out-of-range bank number with a high bit set). Always `I` — no documented expected behavior. |
| `EX2` | Experimental: what happens writing the undocumented value `$C6` to a bank-source register. Always `I`. |
| `TD1` | *(destructive only)* Erases flash sector 7 and confirms it reads back as `$FF`. |
| `TD2` | *(destructive only)* Programs a 128-byte block and reads it back. |
| `TD3` | *(destructive only)* Confirms programming can only clear bits (1→0), never set them back to 1 without an erase. |
| `TD4` | *(destructive only)* Confirms the flash status "done" bit is reported and the polling timeout mechanism works. |
| `TD5` | *(destructive only)* Observes sector-0 write-protect behavior. Always `I`. |
| `TD6` | *(mGBA fixture only)* Requires hidden-map marker `M6TD6FIXTUREONLY` at `$F0-$FF`; otherwise `S` before any hidden-map write. Checks erase, both programmed pages, A/B readback, ready/reset, and WP rejection. Never use on hardware or original save data. |
| `TD7` | *(destructive only)* Programs out-of-order buffer slots and observes which bank/address the repeated-slot trigger commits to. |
| `TD8` | *(destructive only)* Distinguishes `$F0` payload data from `$F0` as a repeated-slot buffer abort. |
| `TD9` | *(destructive only)* Records hidden-map checksums through A/B after sector erase and `$F0`; INFO only. |
| `D10` | *(fixture-only; TD10)* Records JEDEC ID bytes when mode entry and reads use opposite windows. |
| `D11` | *(fixture-only; TD11)* Records immediate and ready status bytes through A/B after buffered program and chip erase. The chip erase destroys all flash. |
| `D12` | *(fixture-only; TD12)* Records bytes at slots 0/127 of the first and last 128-byte pages in sector 7. |

TD6 and TD10–TD12 require both `ENABLE_DESTRUCTIVE_FLASH_TESTS=1` and
`ENABLE_MGBA_FLASH_FIXTURE_TESTS=1`. Never run that build against a physical
cartridge; TD11 performs a whole-chip erase and TD6 erases/programs hidden
map data. TD6 also requires its exact marker in the disposable sidecar; the
ordinary destructive build keeps TD6 as SKIP and does not contain the TD10–TD12
call sites or chip-erase helper.

When TD6 passes in the fixture build, the INFO page's `TD6 RDY A/B` line shows
the ready bytes captured through both windows after the last programmed map
page; the test also reads and checks all 256 map bytes through each window.

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
INFO / A: NEXT

T34 HIDDEN CKSM=$00
T35 SEC0 WP=$80
EX1 BANK $FF DATA:
4D 36 42 4B
EX2 C6ROMFLAG =$00
TD9 MAP A/B=$99/$99
TD10 A>B:$C2/$81
TD10 B>A:$C2/$81
P0 A/B:$00/$00
P1 A/B:$80/$80
C0 A/B:$00/$00
C1 A/B:$80/$80
TD12 0/7F:$A5/$5A
TD12 END:$A5/$5A
```

- **T34 HIDDEN CKSM** — an XOR checksum of the 256-byte hidden flash
  region. No expected value; useful for noticing if it *changes*
  between runs/implementations, not for judging correct vs. incorrect.
- **T35 SEC0 WP** — the raw status byte after entering program/status mode
  without loading buffer data. Bit 1 indicates sector-0 protection in Iceboy's
  Net de Get procedure. The emulator fixtures produced `$80` when unprotected
  and `$82` when protected; the entire byte is retained for observation, not
  compared to either value as a hardware requirement.
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
- **TD9** — XOR checksums for the same hidden-map offsets through A and B.
  A matching pair is a fixture observation, not a general hardware rule.
- **TD10** — manufacturer/device bytes after A-to-B and B-to-A ID mode
  observations. The ID values are documented; cross-window visibility is
  still INFO.
- **TD11 P0/P1/C0/C1** — status snapshots immediately after (0) and after
  bounded polling to ready (1), for program (P) and chip erase (C), shown as
  A/B. Values are observational; the chip erase affects the full flash image.
- **TD12** — readback at offsets `$0000/$007F` (`0/7F`) and `$1F80/$1FFF`
  (`END`) within physical flash bank 112. It records bytes without scoring
  undefined frontier behavior.

## Machine-readable results

If you have a way to inspect SRAM (a savestate, a memory viewer, a
script), `docs/result-format.md` documents a 21-byte struct at SRAM
bank 7 / window B offset `$F00` with the same information as the
results page in binary form — useful for scripted verification
instead of reading the screen.
