# MBC6 technical reference

This document consolidates the MBC6 facts and research that are useful to
emulator authors, cartridge tools, ROM and homebrew developers. It separates
documented requirements from reverse-engineering observations and tests against
specific emulator builds. A result in an emulator fixture is never, by itself,
a hardware specification.

## Evidence labels and source order

- **Documented**: stated by current MBC6 documentation or a cartridge-specific
  technical source. Use this for normative emulator behavior only where the
  source actually makes a requirement.
- **Cartridge observation**: behavior measured or described from Net de Get or
  related flash cartridges, including independent dumper/flasher tools. Strong
  implementation evidence, but not a substitute for an exact-part datasheet.
- **Emulator observation**: observed in a named emulator build and fixture.
  Useful for debugging that implementation, not a hardware conformance rule.
- **Unknown / experimental**: unresolved behavior. Keep it informational; do
  not make it a compatibility failure.

For MBC6-specific claims, consult current [Pan Docs MBC6](https://gbdev.io/pandocs/MBC6.html),
then an exact-part Macronix datasheet if one becomes available, then
[iceboy's NP GB Memory and Net de Get research](https://iceboy.a-singer.de/doc/np_gb_memory.html),
the [GBDev MBC6 research thread](https://gbdev.gg8.se/forums/viewtopic.php?id=544),
and [Dan's Net de Get reverse-engineering notes](https://shonumi.github.io/dandocs.html).
The official [Macronix MX29F800C T/B datasheet](https://www.macronix.com/Lists/Datasheet/Attachments/8539/MX29F800C%20T-B%2C%205V%2C%208Mb%2C%20v1.3.pdf)
is for a related 8-Mbit part, not the exact MX29F008TC-14. Physical cart
markings are catalogued by [Gekkio's Game Boy Hardware Database](https://gbhwdb.gekkio.fi/cartridges/CGB-BMVJ-0/).
Independent implementation references include [FlashGBX](https://github.com/lesserkuma/FlashGBX)
and [sanni/cartreader](https://github.com/sanni/cartreader).

Project-specific source hierarchy, implementation constraints, and test policy
are in [project-rules.md](project-rules.md). [mbc6-notes.md](mbc6-notes.md)
contains dated implementation and emulator findings; [test-matrix.md](test-matrix.md)
is the ROM's test inventory.

## Reading and maintaining this reference

Start here for the mapper and flash protocol. Use [test-matrix.md](test-matrix.md)
to find an executable test and its expected result, [mbc6-notes.md](mbc6-notes.md)
for dated experiments with emulator versions and artifact hashes, and
[result-format.md](result-format.md) to decode the ROM's SRAM results.
These documents are readable without access to the project's private OMM.

When adding a finding, record the source, the evidence label, the date and
relevant version/hash, the test or reproduction procedure, and its limits.
Keep unresolved questions visible. Dated experiments retain their original
provenance even after a newer emulator passes the same test. Paths under
`/tmp` in older experiment notes identify temporary artifacts; their continued
availability is not guaranteed.

## Cartridge and memory architecture

**Documented / physically confirmed:** Net de Get: Minigame @ 100 uses an NEC
MBC6 mapper and a Macronix MX29F008TC-14, a 1 MiB (8-Mbit) NOR flash. Gekkio's
photos show this exact marking on two carts. The board also has 32 KiB SRAM
(one documented unit uses Winbond W24257S-70LL). The flash identifies as JEDEC
manufacturer `$C2`, device `$81`. The flash is eight 128 KiB sectors and has an
additional hidden 256-byte region.

The MBC6 exposes two independent ROM/flash windows and two independent SRAM
windows:

| CPU range | Size | Function |
|---|---:|---|
| `$0000-$3FFF` | 16 KiB | Fixed ROM |
| `$4000-$5FFF` | 8 KiB | ROM/flash window A |
| `$6000-$7FFF` | 8 KiB | ROM/flash window B |
| `$A000-$AFFF` | 4 KiB | SRAM window A |
| `$B000-$BFFF` | 4 KiB | SRAM window B |

ROM/flash bank numbers count 8 KiB units; SRAM bank numbers count 4 KiB units.
Bank 0 is valid in either switchable ROM/flash window. A and B have independent
bank and source selection, so an emulator should not collapse them into one
16 KiB bank latch.

| Register range | Purpose |
|---|---|
| `$0000-$03FF` | SRAM enable |
| `$0400-$07FF` | SRAM bank A |
| `$0800-$0BFF` | SRAM bank B |
| `$0C00-$0FFF` | Flash enable |
| `$1000` | Flash Write Enable / sector-0 and hidden-region protection control |
| `$2000-$27FF` | ROM/flash bank A |
| `$2800-$2FFF` | A source: `$00` ROM, `$08` flash |
| `$3000-$37FF` | ROM/flash bank B |
| `$3800-$3FFF` | B source: `$00` ROM, `$08` flash |

The project's documented power-on snapshot is SRAM disabled, flash disabled,
WE low, A/B source ROM, SRAM banks 0/1, and ROM banks 2/3. Treat this as the
cartridge procedure documented by iceboy and used by this test ROM; capture it
before writing mapper registers.

Any code that changes MBC6 mappings must execute from fixed ROM `$0000-$3FFF`.
Otherwise changing the bank containing the executing code can make execution
undefined. This is also a useful constraint for homebrew bank-switch helpers.

## Flash control and commands

### Enable and protection

FlashGBX and cartreader independently use this enable sequence:

```text
write $1000 = 1
write $0C00 = 1
write $1000 = 0
select flash as the source for A and B
```

Available evidence does not establish whether `$0C00` alone is sufficient. The
sequence above follows the two real-hardware tools. Raise `$1000` again before
an erase/program operation that requires writes. `$1000` is not a general write
enable for all flash: documented behavior associates its protection effect
with sector 0 and the hidden region; sectors 1–7 are not protected by it.

### Address translation for command unlocks

JEDEC-style command writes target flash offsets `$5555` and `$2AAA`. With window
A selecting flash bank 2, CPU `$5555` reaches flash `$05555`; with window B on
bank 1, CPU `$6AAA` reaches `$02AAA`. This is why the ROM helper selects A=2 and
B=1 before the common command sequences. A B-only ID test switches B through
banks 2, 1, 2 to reach the same two flash offsets using CPU addresses
`$7555` and `$6AAA`.

The equivalent A-only unlock maps A=2 for `$AA` at `$5555`, then A=1 for
`$55` at `$4AAA`, then A=2 for the command at `$5555`. The translation is
`flash_offset = selector * $2000 + (CPU_address - window_base)`.
Changing the mapping between writes can therefore reach both unlock offsets
through one window. Net de Get's A-only and B-only helpers provide static
software evidence for this use; they do not establish opposite-window status
visibility.

### Command summary

The following sequences are from iceboy's cartridge-specific procedures, which
state that the flash operation material also applies to Net de Get's 29F008TC.
They are not asserted to come from an exact-part Macronix datasheet.

| Operation | Sequence / behavior |
|---|---|
| Reset / array mode | `$F0`; see the Net de Get reset procedure below |
| JEDEC ID mode | `$AA` at `$5555`, `$55` at `$2AAA`, `$90` at `$5555`; reads return `$C2`, `$81` |
| Hidden-map read mode | Repeat twice: `$AA` at `$5555`, `$55` at `$2AAA`, `$77` at `$5555`; read the hidden 256-byte region; exit with reset |
| Sector erase | `$AA/$55/$80`, then `$AA/$55/$30` at an address in the target sector |
| Mass erase | `$AA/$55/$80`, then `$AA/$55/$10`; iceboy describes erasing the 1 MiB array, preserving the hidden map, with sector 0 conditional on write/sector protection |
| Buffered program | `$AA/$55/$A0`, then write bytes into one 128-byte aligned page and repeat the immediately previous slot/address to trigger programming |
| Hidden-map erase | `$AA/$55/$60`, then `$AA/$55/$04` |
| Hidden-map program | `$AA/$55/$60`, then `$AA/$55/$E0`, followed by the 128-byte buffer procedure |

Iceboy's Net de Get `is_sector0_protected()` probe enters program/status mode
with `$AA/$55/$A0` while write protection is enabled, reads status bit 1 at
`$4000`, and calls the reset procedure immediately. It writes no buffer
payload and issues no repeated-slot trigger, so this is a read-only status
observation and does not start persistent programming. The Test ROM reports
the raw byte as INFO; it does not prescribe whether an individual cart must
have sector 0 protected.

During buffered programming, the repeated write is the trigger. It repeats the
most recently written slot. The trigger address selects the destination page and
bank; the data bytes may be loaded out of order. `$F0` is ordinary payload
unless it is the repeated final trigger slot, where it aborts the pending buffer
instead of committing it. This trigger/abort description comes from iceboy's
Net de Get pseudocode and is implemented in the destructive fixture tests; it
has not been independently verified on physical hardware by this project.

Flash status bit 7 is the documented ready/completion indicator. Dan's
reverse-engineering notes report that Net de Get checks bit 4 as a timeout
indicator; iceboy describes bits 5–4 as driven but unknown (observed low).
Therefore, treat bit 4 as a cartridge-code observation until stronger
evidence resolves the discrepancy. Poll with a bounded software timeout, save
the last status byte, and reset if safe; never wait forever on an incomplete
emulator. Exact cross-window status visibility and timing are not established
as hardware requirements in the reviewed sources.

### Net de Get `Flash_Reset`

The cartridge-specific procedure is: enable flash and map both windows to
flash, write `$F0` twice at `$4000`, wait 100 ms, then write `$F0` once more at
`$4000`. Iceboy explains that the first pair abandons an unfinished write
buffer, while the delayed write handles an erase/program operation that ignored
the early resets. The related official Macronix datasheet supports the general
meaning of `$F0` (including leaving ID mode/incomplete commands), but does not
document this three-write sequence or its delay. Preserve the distinction.

## Emulator and tool implementation notes

### Net de Get software sequence and offline coverage

**Static cartridge-code observation, reviewed 2026-10-06:** the companion
Net de Get disassembly identifies these routines in the image with SHA-256
`9fb1e6e4a637796b8624bd2de6c9abaa9e758546b620cb5dc8441b07c288bc63`.
Addresses below are fixed-ROM CPU addresses, also file offsets in this image.
They identify the investigated revision, not a portable host API contract.
No cartridge ROM bytes are included in this repository.

| Operation | Host location | Observation / Test ROM coverage |
|---|---|---|
| Independent bank/source latches | A `$12E9-$12F7`, B `$12BF-$12CD` | Writes selector and source separately; T10-T14 and T30 exercise mapping and isolation. |
| Single-window unlock | A `$164D-$1662`, B `$14E2-$14F7` | Switches the operation window through selectors 2 and 1; T32 uses B-only unlock, whereas the common Test ROM helper uses A=2/B=1. |
| Sector erase | A `$14F8-$1519`, B `$1390-$13AF` | Unlock/`$80`, unlock/`$30` at the selected window; TD1 exercises sector-7 erase and array readback. Some host routine boundaries remain ambiguous. |
| Staged buffered programming | A entry `$1568`, caller B selector 6 `$61F4-$620B` | Caller supplies a 4 KiB WRAM buffer at `$D000`; writer consumes chunks of at most 128 bytes and checks readback. TD2/TD7/TD8/TD12 cover individual buffer and trigger cases, rather than this complete host workflow. |
| Flash dispatch and return | `$026D` to `$254E` | For an index at least `$10`, subtracts `$10`, selects A flash, calls `$4000`, then restores ROM mapping. Executing an installed payload and returning is not currently a Test ROM test. |

The reviewed writer repeats the last loaded address with trigger value zero;
the trigger does not replace the buffered payload. It polls status, writes a
single `$F0` before array readback and checks the source bytes. This is a
software sequence for an operation expected to have completed. It does not
replace Iceboy's `Flash_Reset` procedure for an unfinished buffer or busy
operation. Host polling checks DQ4 during program and DQ5 during erase;
these software checks do not settle the chip's undocumented status semantics.

The Test ROM runs without a server or Mobile Adapter. A separate opt-in
[offline workflow fixture](net-de-get-offline.md) stages two 4 KiB WRAM chunks,
programs 64 pages, checks all 8 KiB through A/B, executes an original homebrew
payload and verifies return/restoration. Its host runner measures persistence
by reopening a fresh core; an in-ROM readback alone cannot demonstrate it.
The fixture has its own result annex and requires all destructive fixture
gates plus a hidden-map marker. It does not reproduce the original game's
checksum/header, decompressor or network installation route.

For dated Test ROM execution evidence, see the 2026-10-06 entries in
[mbc6-notes.md](mbc6-notes.md): mGBA `358230c82` returned
15 PASS / 0 FAIL / 0 SKIP / 5 INFO for the default ROM and
22 PASS / 0 FAIL / 0 SKIP / 10 INFO for the marked disposable fixture.
Those earlier runs validate the original suite cases in that emulator;
they predate the integrated offline fixture and do not validate it or
establish physical cartridge behavior.

### Implementation guidance

- Model flash command parsing separately from ROM bank mapping. Keep A/B bank
  and source latches independent, and decode flash writes only when the window
  is mapped to flash and the relevant flash controls permit access.
- Distinguish ROM bank numbers (8 KiB) from SRAM bank numbers (4 KiB).
- Preserve the flash array, ID mode, hidden-map mode, status/busy state, and
  pending buffer state consistently across reads, reset, save files, and
  savestates. These are implementation recommendations from the command model;
  persistence container formats are emulator-specific.
- FlashGBX and cartreader agree on the enable sequence and remap both A and B
  to the target bank before writes. The current ROM's helpers write commands
  through A; whether hardware requires both windows to target the same bank is
  not established here.
- The related MX29F800C datasheet is useful for generic NOR command context only.
  The AMD Am29F400B datasheet linked from iceboy is likewise a similar-command
  example, not an authority for this chip's 128-byte buffer or hidden region.

The project has run flash tests against specific, locally built mGBA and GBE+
versions. Those results—including missing or implemented commands, `.sav.flash`
layout, busy timing, and savestate behavior—are version/build-specific. Read
the dated evidence in [mbc6-notes.md](mbc6-notes.md) before using it to make
claims about a release. A fixture result is not physical cartridge validation.

## Open questions and experimental behavior

- No first-party datasheet for the exact MX29F008TC-14 has been located.
- Iceboy identifies the hidden map as mapping configuration consumed by the
  cartridge mapper, but the original Net de Get map contents and their
  application-specific interpretation are not established here. Read-only
  observations are INFO; erase/program belongs only in disposable fixtures.
- The GBDev research thread contains unresolved behavior around high bank bits
  and writes such as `$C6` to source/type registers. Keep these experimental.
- Whole-chip erase command `$10` appears in an older archived Pan Docs table,
  and the current iceboy page also documents `$80/$10` with a Net de Get
  procedure. This is cartridge research, not an exact-part manufacturer
  datasheet; TD11 remains a destructive fixture observation, not a normative
  hardware test.
- The board's Mitsumi MM1134A supervisor/reset IC is visible on documented
  carts, but its software-visible interaction with MBC6 registers is unknown.
- Exact reset timing, cross-window command/status visibility, and whether both
  windows must map the destination bank remain incompletely specified.

Do not run destructive test builds on physical cartridges or valuable saves.
The repository's fixture-only gates and current test status are described in
[project-rules.md](project-rules.md) and [test-matrix.md](test-matrix.md).
