# Implementation notes

Working notes on non-obvious behavior discovered while building and
testing this ROM. See `docs/test-matrix.md` for the formal per-test
list; this file is for things worth recording that don't fit a single
test row.

## BGB was not available to test against during initial development

This project's stated motivation (`docs/project-rules.md`, `README.md`) is
interoperability testing requested by the BGB developer — but BGB is
understood to not currently have (or not yet have complete) MBC6
support, which is exactly why a conformance ROM like this is useful to
that developer in the first place: it's a tool to develop/validate
MBC6 emulation against, not evidence that BGB already passes it. GBE+
and mGBA were used instead for the cross-validation described below,
since both already have some MBC6 support (with the gaps noted
elsewhere in this file). Whoever next has a BGB build with MBC6
support should treat that as the first real test of this ROM against
its original target, not a formality — don't assume it will pass
just because GBE+/mGBA did.

## `.gbc` file extension matters on at least one emulator

This ROM's header already declares CGB-only mode (`$0143 = $C0`), which
should be unambiguous. In practice, mGBA (0.11 dev build) rendered
`CGB REQUIRED` — i.e. it ran the ROM in DMG mode despite the header —
when the file was named `mbc6-test.gb`, and ran correctly in CGB mode
once the exact same bytes were renamed to `mbc6-test.gbc`. GBE+ was
unaffected by the extension either way.

Consequence: the Makefile emits `build/mbc6-test.gbc`, not `.gb`.
Emulator/hardware developers testing this ROM should keep the `.gbc`
extension (or check their emulator's mode-override settings) rather
than relying on the header alone.

## `rSVBK` ($FF70) unused bits are not guaranteed zero on readback

The CGB-capability probe in `src/main.asm` (`DetectCGBCapability`)
writes a WRAM-bank value to `rSVBK` and reads it back to confirm CGB
hardware is present, independent of any boot-ROM hand-off register.
Bits 3-7 of `rSVBK` are unused by the register's function; an early
version of this probe compared the raw byte and produced a false "not
CGB" result on mGBA (which reads those bits back as 1), while GBE+
happened to return them as 0 and did not expose the bug. The probe now
masks with `$07` before comparing. Treat any other CGB-only I/O
register probe the same way — don't assume unused bits read as zero
without checking more than one implementation.

## Cross-checked against two independent MBC6 implementations

The safe ROM/SRAM test suite (T00, T01, T10-T14, T20-T24) has been run
to completion in both GBE+ (via Wine) and mGBA 0.11, and both report
`P:11 F:00 S:00 I:01` — full pass, no failures, one INFO test (T00).
This is evidence the test logic and both emulators' MBC6/CGB
implementations agree on this subset of behavior; it is not proof of
correctness against real hardware.

## T31/T32/T33 (flash JEDEC ID) FAIL on both GBE+ and mGBA — confirmed emulator gap, not a test bug

With T30-T35 added, both emulators report `P:12 F:03 S:00 I:03`: T30
(source-selection isolation) and T34/T35 (INFO) behave as expected,
but T31, T32, and T33 (which all depend on reading back the JEDEC
manufacturer/device ID after the documented autoselect entry sequence)
FAIL on both.

This was root-caused by reading each emulator's own MBC6 source, not
by guesswork (docs/project-rules.md: never infer hardware truth from an emulator,
but reading an emulator's source to debug *this ROM's* code, without
changing the ROM's documented-behavior expectations, is a legitimate
debugging step):

- **GBE+** (`src/dmg/mbc6.cpp`, `shonumi/gbe-plus`): the `0x90`
  (autoselect/ID) command sets `cart.flash_get_id = true`, but that
  flag is never read anywhere in `mbc6_read()` — both flash read paths
  are marked `// TODO` and just index into the raw `flash[]` array.
  ID-mode reads silently fall through to ordinary array reads.
- **mGBA** (`src/gb/mbc/mbc.c`, local build in
  `MobileAdapterGB/mgba`): `_GBMBC6()` logs `"MBC6 unimplemented flash
  OE write"` for the $0C00 (Flash Enable) range and `"...flash WE
  write"` for $1000 (`mLOG(..., STUB, ...)`). Source select
  ($2800/$3800) *is* implemented (`_GBMBC6MapChip`, bit 3 of the
  value), and a flash-sourced window reads the last 1 MiB of the save
  buffer (`GBMBCSwitchHalfBank` in `src/gb/mbc.c`), so flash *reads*
  work. But writes to $4000-$7FFF fall through to the `"MBC6 unknown
  address"` stub, so no flash command (ID, erase, program, reset) is
  ever interpreted, and reads keep returning the array contents —
  `$FF` on a fresh save, since new save space is filled with `$FF`
  (`src/gb/gb.c`). *(Corrected 2026-10-04: an earlier version of this
  note attributed the OE stub to $2800/$3800 and said flash reads were
  not handled.)*

Versions involved (identified 2026-10-04): the GBE+ runs used the
official **GBE+ 1.10** Windows release (tag `1.10`, commit
`f4c6e1f26407`; same SHA-256 as the release's `gbe_plus.exe`), while
the source read during development was GBE+ **master** at
`33346a290d42` (2026-06-10, "fix MBC6 bank erasing") — line numbers
quoted at the time match master, not 1.10. The mGBA build reported
itself as `0.11-9175-717fb3fd0-dirty`; its committed MBC6 code is
unchanged up to the local HEAD checked on 2026-10-04, but the
uncommitted ("-dirty") changes of that build are unknown.

## Results are shown on-screen, not just inferred from a summary count

An early version of this ROM only showed the P/F/S/I summary and a
single cramped hex line for the first failure — enough to prove the
underlying test logic was correct (verified independently via a Lua
script reading the raw result-block bitset in SRAM), but not enough
for someone looking at the actual screen to see *which* of the 26
tests did what, the way `mbc30test`-style ROMs show a live grid. The
UI now has three pages, cycled with A (`src/ui.asm`
`UI_ResultsLoop`): a full results grid (every test ID + PASS/FAIL/
SKIP/INFO/`-` for "didn't run this build"), a failure detail page
(test ID, bank, full 16-bit address, expected/actual byte), and an
INFO/experimental page (T34's checksum, T35's status byte, EX01's
observed bytes, EX02's flag). With `ENABLE_DESTRUCTIVE_FLASH_TESTS=1`
and the on-screen confirmation held, the full run (safe + TD1-TD8)
reports `P:21 F:00 S:01 I:06` on the local mGBA `feature/full_server`
working tree (base `d80a87ee` plus uncommitted changes), with a valid M6TS
checksum. TD7 and TD8 pass there for out-of-order partial programming,
trigger-address bank selection, `$F0` payload, and repeated-slot abort.
The safe run is `P:15 F:00 S:00 I:05`. This is development-tree evidence;
it does not establish behavior in a released mGBA build or on hardware.

One bug worth recording: `wPrevJoypad` (used to edge-detect the A
press that advances a page) was originally seeded to 0 on entry to
`UI_ResultsLoop`. If the player is still physically holding A when
that loop starts — quite likely right after holding A+B+START to
confirm a destructive run — that fake "nothing held" baseline reads
as a fresh press and skips a page immediately. Fixed by seeding it
from a real `ReadJoypad` call instead. Caught by testing the actual
button-hold-through-transition sequence in mGBA via a scripted input
sequence, not by inspection.

Neither emulator returns the JEDEC ID: GBE+ ignores ID mode on reads,
and mGBA does not interpret flash commands at all. The command sequence
this ROM sends is the one documented in iceboy's Nintendo Power GB
Memory (NP GB Memory) reference (see `src/flash.asm` and "About the
iceboy source" below); the expected `$C2`/`$81` result is normative per that
source, so T31-T33 correctly report FAIL rather than being weakened to
match either emulator's current behavior — that would defeat the
purpose of a conformance suite. This is exactly the kind of gap
report this project exists to produce; it is not evidence of a bug in
this ROM.

## More MBC6 flash sources, and the changes they prompted

Rafael pointed at four more sources partway through development:
dandocs, FlashGBX, `wodowiesel/GB-Dumper` and `sanni/cartreader`.
GB-Dumper turned out to be irrelevant to MBC6 (MBC1/2/5 pinouts only).
The other three were significant:

- **Dan/shonumi's dandocs** (<https://shonumi.github.io/dandocs.html>,
  "Net de Get: Mini Game @ 100" → "MBC6 Flash Operation"). Written by
  GBE+'s author, based on reverse-engineering the real game's code —
  not a datasheet, but primary research grounded in how the one real
  MBC6 title actually drives the chip.
- **FlashGBX** (github.com/lesserkuma/FlashGBX,
  `FlashGBX/Mapper.py`, class `DMG_MBC6`) and **sanni/cartreader**
  (github.com/sanni/cartreader, `Cart_Reader/GB.ino`,
  `readSRAMFLASH_MBC6_GB`/`writeSRAMFLASH_MBC6_GB`). Both are
  real-hardware cartridge dumper/flasher tools with independent MBC6
  flash implementations, used against physical Net de Get carts by
  their communities. Their command sequences agree with each other in
  every detail, which carries real weight — this isn't one source's
  guess, it's two independent tools converging on the same bytes.

### Flash reset follows the Net de Get-specific documented procedure

1. **`Flash_Reset` follows iceboy's Net de Get-specific pseudocode.**
   After enabling flash and mapping both windows to flash, it writes
   `$F0` twice to `$4000`, waits 100 ms, then writes `$F0` there once
   more. The source says the first pair exits a pending write-buffer
   load without starting programming, and the delayed write handles an
   erase/program operation that ignored the earlier resets. This
   procedure is based on the author's investigation and measurements
   of Net de Get/related cartridges; it is not an official Macronix
   datasheet. Pan Docs identifies the Net de Get flash as Macronix
   MX29F008TC-14. We did not find a first-party datasheet for that exact
   part. Macronix's official MX29F800C T/B datasheet is a related 8-Mbit
   NOR reference: its reset table specifies `$F0` at any address, and
   its reset section lists exit from silicon-ID mode and incomplete
   command sequences. That supports the general meaning of `$F0`, but
   does not establish the Net de Get-specific three-write sequence or
   its 100 ms delay. Those details remain grounded in iceboy's
   cartridge-specific pseudocode and measured operation timings. The
   former one-per-window sequence was motivated by GBE+'s emulator
   behavior; that observation is not evidence to override the
   documented cartridge procedure.
2. **The buffered-write "commit" byte repeated the real data value
   instead of writing literal `$00`.** An earlier version's commit
   step was `ld a,[hl] / ld [hl],a` — re-write whatever value was
   already there. Both dandocs ("it writes a 0x00 at the very last
   byte") and cartreader's code (`writeByte_GB(romAddress - 1, 0x00);`
   as a distinct step right after the 128-byte data loop, which had
   already written that same address once with real data) confirm the
   commit is a second, separate write of literal 0 — exactly the fix
   now in place: after the loop writes real data to the last byte, a
   second `xor a` / `ld [hl],a` writes `$00` there specifically.
   GBE+'s finish-signal check (`value == 0`) needs exactly that
   literal value to fire.

Neither change made TD1-TD3 pass in GBE+; the next section explains
why. The commit-byte change (item 2) stands on two
independently-converging real-hardware sources.

### Why TD1-TD3 still fail in GBE+ (corrected 2026-10-04)

After both changes, TD1 in GBE+ still showed `TEST ID $14`, bank `$70`,
address `$4000`, expected `$FF`, actual `$F0`. During development this
was blamed on a bank-selection bug, but checking GBE+ 1.10's code (the
binary actually run) shows a different cause:

- GBE+ stores *any* write to $4000-$7FFF that is neither a command nor
  the end of a pending operation as data in `flash[flash_io_bank]`, in
  either window, without even checking whether that window is sourced
  from flash. `Flash_Reset` writes `$F0` to $4000 and then to $6000:
  the first ends the pending erase status, the second is stored as
  data at offset 0 of the erased bank — exactly the `$F0` seen at
  `$4000`.
- In GBE+ 1.10, sector erase also fills the bank with `$00` instead of
  `$FF` (fixed upstream in `33346a290d42`, 2026-06-10, after 1.10), so
  the other checked offsets would read `$00` too (inferred from the
  code; the ROM reports only the first failure).
- TD2/TD3 probably fail through the same stored-as-data path,
  overwriting the first programmed byte (inference, not verified).

The bank-selection bug itself is real — the flash-command handler
computes window A's bank from `bank_bits` (the *SRAM*-banking
variable, `$0400`/`$0800`) instead of `rom_bank`:

```c
u8 bank_0 = (bank_bits & 0x7F);        // used for window A (address < 0x6000)
u8 bank_1 = ((rom_bank >> 8) & 0x7F);  // used for window B
```

so every flash command through window A targets physical flash bank 0
(the "remembered" `flash_io_bank`). But flash reads go through the
same `flash_io_bank`, so that bug alone does not produce TD1's
mismatch.

**Ruled out another possible explanation**: GBE+ persists flash contents to a `<romname>.sav.flash` file
next to the ROM, separate from the regular `.sav` (SRAM). Since this
ROM's `build/mbc6-test.gbc` was repeatedly rebuilt and copied to the
same path in `emulador/` throughout this investigation, a stale
`.sav.flash` from an earlier session could in principle have
contaminated a later one (emulators typically key save files off the
ROM's filename, not its contents/hash). Re-ran TD1 against a
never-before-used filename with no pre-existing `.sav`/`.sav.flash` —
identical result (`TD1:F TD2:F TD3:F TD4:P`), so leftover state from a
previous run was not the cause. It is still worth knowing about
`.sav.flash` when re-testing this ROM in GBE+, since it silently
persists across otherwise-fresh runs of the same filename.

None of these behaviors is documented hardware behavior (neither
iceboy, dandocs nor either dumper tool describes anything like them),
so `Test_TD1` is not adapted to route around them — doing so would
encode emulator bugs as expected behavior, exactly what
docs/project-rules.md's sourcing rules exist to prevent. TD1-TD3
reporting FAIL against GBE+ 1.10 is the correct, informative outcome.

### The `$1000` → `$0C00` → `$1000` enable sequence is real, not guesswork

Both FlashGBX and cartreader enable flash the same way, in the same
order, independently:

```text
write $1000, 1   ; Flash Write Enable, momentarily
write $0C00, 1   ; Flash Enable
write $1000, 0   ; (or 1, only when the caller actually intends to write)
write $2800, 8   ; source A = flash
write $3800, 8   ; source B = flash
```

This ROM previously only ever wrote `$0C00` — docs/project-rules.md documents
`$1000` as sector-0/hidden-region write protection, which doesn't on
its face suggest it gates `$0C00` at all. Whether `$0C00` alone would
have worked isn't known from any source consulted; rather than guess,
`Flash_SelectCommandWindows` now follows the sequence both real-
hardware tools use, and the destructive write/erase helpers raise
`$1000` again immediately before the command that actually writes,
matching cartreader's write path exactly (`$1000,1` again right
before the erase/program commands, dropped back down by `Flash_Reset`
implicitly disabling flash write after the operation completes).

### One more confirmed-safe pattern not yet adopted here

Both real-hardware tools remap *both* ROM Bank A and ROM Bank B to the
actual target bank before issuing a program/erase command, not just
the one window this ROM's helpers write through. Since none of this
ROM's flash helpers read or write via window B during a command, this
doesn't change any observed behavior — noted here as a known
divergence from the confirmed-working pattern, in case a future
emulator or hardware revision turns out to care.

## Physical hardware confirmation: gbhwdb (Gekkio)

Two real Net de Get carts are individually photographed and documented
at gbhwdb.gekkio.fi (`cartridges/CGB-BMVJ-0/gekkio-1.html` and
`gekkio-2.html`). Both are board type `CGB-A32-01`, manufactured May
2001. Confirms, from an independent physical-hardware source rather
than a software reverse-engineer's notes:

- **Flash chip**: exact part number `MX29F008TC-14`, manufacturer
  Macronix — matches `docs/project-rules.md`'s stated part number precisely, now
  with visible chip markings from two physical units
  (`E991012 29F008TC-14 21534 TAIWAN` and
  `E991112 29F008TC-14 21726 TAIWAN`), not just a document reference.
- **SRAM**: Winbond `W24257S-70LL`, a 32K×8 SRAM — consistent with the
  header's `$0149 = $03` (32 KiB).
- **Mapper IC**: marked `Nintendo MBC6`, made by NEC.

One component not mentioned in any other source consulted for this
project: a **Mitsumi `MM1134A` supervisor/reset IC**, present on both
units. This is a battery-backed-SRAM voltage supervisor (holds reset
or blocks writes on brownout/low battery) — plausible circuitry for a
cartridge with 32 KiB of battery-backed SRAM, but nothing in the
sources consulted here says whether it interacts with the MBC6's own
registers (e.g. whether it's involved in `$1000`'s write-protect
behavior) or is purely a passive power-supervision component wired
independently. Recorded as INFO for anyone investigating further, not
acted on in this ROM — no source describes a testable software-visible
effect from it.

## About the iceboy source ("NP GB Memory")

The primary flash reference
(<https://iceboy.a-singer.de/doc/np_gb_memory.html>, Michael Singer)
is titled "Nintendo Power Game Boy Memory cartridge documentation".
"NP GB Memory" is the white Nintendo Power Game Boy Memory flash
cartridge sold in Japan — a different cartridge from Net de Get. The
author notes that Nintendo Power cartridges use a 29F008ATC (device ID
`$89`) and Net de Get a 29F008TC (device ID `$81`), found no other
difference between the two flash chips (same erase sector size, same
256-byte hidden region), and states that the flash part of the page
also applies to Net de Get. The page has its own section of
pseudocode procedures for Net de Get (MBC6) cartridges.

The datasheet linked from that page is for the AMD Am29F400B, cited by
the author only as "a flash that has a command set that looks
similar". It shares the generic command codes this ROM uses (`$F0`
reset, `$AA`/`$55` unlock, `$90` autoselect, `$80`…`$30` sector erase,
`$A0` program), but differs in unlock addresses, single-byte
programming (no 128-byte buffer), status bits (DQ7/DQ6/DQ5) and has no
hidden region, so it cannot validate anything MBC6-specific and is not
an authority for this project (checked 2026-10-04).
### TD9 cross-window hidden-map fixture (2026-10-06)

Added a destructive, fixture-only observation after a completed sector-7
erase and `$F0`: enter hidden-map mode and XOR the same 256 local offsets
through windows A and B independently. The two values are INFO only because
the reviewed sources do not establish cross-window equality as a hardware
requirement.

Validated with the disposable headless fixture against the mGBA core built
from the current `feature/mbc6-complete` checkout (base commit
`fca224b25`, local uncommitted cross-window fix). The `.sav.flash` fixture
contained `$66` at hidden-map index 5 and `$FF` elsewhere. The ROM completed
with M6TS v2.2 `P:21 F:0 S:1 I:7`; TD9 status was INFO and its A/B checksums
were both `$99`, matching the fixture. The result-block checksum verified.
This validates the ROM observation path against that emulator build and
fixture only; it is not hardware evidence.
