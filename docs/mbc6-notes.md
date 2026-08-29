# Implementation notes

Working notes on non-obvious behavior discovered while building and
testing this ROM. See `docs/test-matrix.md` for the formal per-test
list; this file is for things worth recording that don't fit a single
test row.

## BGB was not available to test against during initial development

This project's stated motivation (`CLAUDE.md`, `README.md`) is
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
by guesswork (CLAUDE.md: never infer hardware truth from an emulator,
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
  OE write"` / `"...flash WE write"` (`mLOG(..., STUB, ...)`) for the
  $2800/$3800 and $1000 register ranges and has no case at all for
  writes to $4000-$7FFF when sourced from flash; `_GBMBC6Read()` has no
  flash-array or ID-mode handling either.

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
and the on-screen confirmation held, the full run (safe + TD1-TD6)
reports `P:14 F:05 S:01 I:06` on mGBA — TD1 (erase) and TD4 (status/
timeout) PASS, TD2 (buffered program) and TD3 (1->0 semantics) FAIL,
consistent with the same incomplete flash command emulation noted
above; TD5 is INFO and TD6 is SKIP by design (see `docs/test-matrix.md`).

One bug worth recording: `wPrevJoypad` (used to edge-detect the A
press that advances a page) was originally seeded to 0 on entry to
`UI_ResultsLoop`. If the player is still physically holding A when
that loop starts — quite likely right after holding A+B+START to
confirm a destructive run — that fake "nothing held" baseline reads
as a fresh press and skips a page immediately. Fixed by seeding it
from a real `ReadJoypad` call instead. Caught by testing the actual
button-hold-through-transition sequence in mGBA via a scripted input
sequence, not by inspection.

Neither emulator implements the flash command interface beyond basic
ROM/SRAM bank switching. The command sequence this ROM sends is the
one documented in the iceboy NP GB Memory reference (see
`src/flash.asm`); the expected `$C2`/`$81` result is normative per that
source, so T31-T33 correctly report FAIL rather than being weakened to
match either emulator's current behavior — that would defeat the
purpose of a conformance suite. This is exactly the kind of gap
report this project exists to produce; it is not evidence of a bug in
this ROM.

## Three more MBC6 flash sources, and two real bugs they caught

The user pointed at three more sources partway through development.
Two turned out to be irrelevant to MBC6 (`sanni/cartreader`'s GB
support covers it, see below, but `wodowiesel/GB-Dumper` doesn't
mention MBC6 at all — MBC1/2/5 pinouts only). The other two were
significant:

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

### Two real bugs in this ROM's flash.asm, found and fixed

1. **`Flash_Reset` wrote `$F0` twice per window.** The iceboy doc
   suggests a second reset "if the chip is in an unknown state," and
   an earlier version of this ROM took that literally — write `$F0`,
   then write it again to the same address. Traced against GBE+'s
   source (`src/dmg/mbc6.cpp`): a `$F0` write only *terminates* a
   pending status (`flash_stat & 0x81`) — once the first `$F0` already
   cleared that, a *second* `$F0` to the same address instead falls
   through to the ordinary array-write path and gets stored as data,
   corrupting the byte it just erased/programmed. Confirmed by
   reproducing it: TD1 read back `$F0` instead of `$FF` at the exact
   offset the (second) reset had been written to. Neither FlashGBX nor
   cartreader ever issue a repeated `$F0` to the same address — each
   sends it exactly once. Fixed the same way here.
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

Neither fix changed GBE+'s TD1-TD3 results, because GBE+ has a third,
separate bug unrelated to either of the above (see next section) — but
both fixes are still correct per two independently-converging
real-hardware sources, and are worth keeping regardless of what any
one emulator currently does with them.

### A third bug — this one in GBE+, not this ROM

TD1 (sector erase) still reads back the wrong byte in GBE+ after both
fixes above. Traced to `src/dmg/mbc6.cpp`'s flash-command write
handler:

```c
u8 bank_0 = (bank_bits & 0x7F);        // used for window A (address < 0x6000)
u8 bank_1 = ((rom_bank >> 8) & 0x7F);  // used for window B
```

`bank_1` (window B) correctly reads `rom_bank`, the variable that
`$2000`/`$3000` writes actually update. `bank_0` (window A) reads
`bank_bits` instead — the *SRAM*-banking variable (`$0400`/`$0800`),
never touched by this ROM before flash tests run. Compare the
non-flash ROM-read path in the same file, which correctly uses
`bank_0 = (rom_bank & 0x7F)`. Since `bank_bits` stays at its
zero-initialized default, every flash command issued through window A
in GBE+ silently targets physical flash bank 0 regardless of what's
written to `$2000` — confirmed by tracing `flash_io_bank`'s value
through `case 0x30` and the read path, both of which only branch on
this same miscomputed `bank_0`.

**Ruled out a second possible explanation before settling on the
above**: GBE+ persists flash contents to a `<romname>.sav.flash` file
next to the ROM, separate from the regular `.sav` (SRAM). Since this
ROM's `build/mbc6-test.gbc` was repeatedly rebuilt and copied to the
same path in `emulador/` throughout this investigation, a stale
`.sav.flash` from an earlier session could in principle have
contaminated a later one (emulators typically key save files off the
ROM's filename, not its contents/hash). Re-ran TD1 against a
never-before-used filename with no pre-existing `.sav`/`.sav.flash` —
identical result (`TD1:F TD2:F TD3:F TD4:P`). This confirms the
`bank_bits` mixup above as the actual cause, not leftover state from a
previous run; still worth knowing about `.sav.flash` when re-testing
this ROM in GBE+, since it silently persists across otherwise-fresh
runs of the same filename.

This is a real bug in GBE+, not a documented hardware quirk (neither
dandocs nor either dumper tool describes anything like it), so
`Test_TD1` is not adapted to route around it — doing so would encode
an emulator bug as expected behavior, exactly what CLAUDE.md's
sourcing rules exist to prevent. TD1-TD3 reporting FAIL against this
specific GBE+ build is the correct, informative outcome.

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

This ROM previously only ever wrote `$0C00` — CLAUDE.md documents
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
  Macronix — matches `CLAUDE.md`'s stated part number precisely, now
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
