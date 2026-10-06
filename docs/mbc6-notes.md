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

### TD6 hidden-map fixture (2026-10-06)

Added TD6 behind both destructive-build flags and an exact 16-byte fixture
marker (`M6TD6FIXTUREONLY`) at hidden-map offsets `$F0-$FF`. The ROM checks the
marker before issuing any hidden-map command; an absent/mismatched marker
records SKIP. With the marker present, it erases and verifies all 256 bytes as
`$FF` through A and B, programs the first 128-byte half with `$10` and the
second with `$80`, checks ready status through both windows and `$F0` reset,
then attempts erase and program with WE disabled and verifies all 256 bytes
remain unchanged. The fixture-only warning calls out map and chip erase.

Validated using ROM `/tmp/mbc6-test-TD6-fixture-411ba0b-plus.gbc` (SHA-256
`9c7ba52875477cbac004a28656e7de68045bcf4add7aa24e373fdeee46068501`) and
`/tmp/mgba-mbc6-qt-verify/libmgba.so.0.11.0` (SHA-256
`c5a48043623e81b99b908b5ae226363cf7b682f95c523b129440c51aa1e5d514`). Runtime
returned `M6TS fmt=2 suite=3 P/F/S/I=22/0/0/10 TD6=PASS`, busy `00/00`, ready
`80/80`, and valid checksum. With a fresh all-`$FF` map lacking the marker,
TD6 returned SKIP and all 256 bytes remained `$FF`. After closing and
reopening mGBA, the saved map still contained 128 `$10` bytes followed by 128
`$80` bytes; the second launch also skipped TD6 because the erase had removed
the fixture marker. The ordinary destructive build was also runtime-checked
and kept TD6 at SKIP even with the marker present. All sidecars and ROMs were
confined to `/tmp`. This is mGBA fixture evidence only, never a hardware result.

### Source correction: mass erase documentation (2026-10-06)

An earlier TD11 source description said `$80/$10` appeared only in an archived
Pan Docs table. Rechecking the current iceboy page disproved that: its flash
command section documents mass erase (`$AA/$55/$80`, then `$AA/$55/$10`), says
it erases the 1 MiB flash while preserving the hidden 256-byte map, and gives a
Net de Get pseudocode procedure. Sector 0 is preserved when write or sector-0
protection is enabled. This is cartridge-specific research, not a first-party
MX29F008TC-14 datasheet; TD11 remains a destructive mGBA fixture observation.
The current source and evidence classification are summarized in
[`mbc6-reference.md`](mbc6-reference.md).

The same source check clarified status bit 4: Dan Docs reports that Net de Get
checks it as a timeout indicator, while iceboy classifies bits 5–4 as driven but
unknown (observed low). The reference and project rules now preserve that
uncertainty instead of presenting bit 4 as a settled chip-level requirement.

### Independent coverage review against mGBA `4c8066be4` (2026-10-06)

Read-only review of the collaborating mGBA checkout at clean
`feature/mbc6-complete` commit `4c8066be4`, compared with the Test ROM sources:

- **TD4 did not test DQ4.** `Test_TD4` calls the bounded `Flash_PollStatus`,
  which checks ready bit 7 and reports if the ROM's software iteration limit
  expires. `FLASH_STATUS_TIMEOUT_BIT` is defined but unused. The previous
  matrix wording implied that chip status bit 4 was tested; it is now corrected.
  mGBA's status reads in `src/gb/mbc/mbc.c` expose ready bit 7 and protection bit
  1, but not bit 4. Given the Iceboy/Dan Docs evidence disagreement above, treat
  DQ4 as an open compatibility observation, not a required behavior.
- **T35 did not read protection status.** It selects flash bank 0 and records
  array byte 0 without entering the flash status mode. The test remains INFO,
  now named and documented as an array-byte sample. Iceboy's non-destructive
  procedure enters program/status mode, samples bit 1 before any buffer trigger,
  then resets; this could replace the raw sample if we want a useful protection
  observation without changing persistent protection state.
- **T30 did not prove A/B source-latch independence.** It toggles both source
  registers before checking the signatures, so cross-coupled A/B source latches
  could escape detection. The matrix now calls its coverage partial. A stronger
  check should change one source at a time and inspect the other window before
  touching that window; known flash contents may require a disposable seeded
  fixture if a definitive array/source assertion is needed.

The T35, TD4 code comments and matrix descriptions were adjusted to match the
actual observations. At that review point T30 remained incomplete and T35 still
sampled raw array data; the follow-up below records the completed fixes.

The mGBA implementation paths reviewed include independent flash-source/bank
mapping, command parsing, buffer trigger/abort, busy completion, protection,
hidden map, and serialized operation state (`src/gb/mbc/mbc.c` and
`src/gb/memory.c`). This source review found no contradiction in those paths
with the fixture cases TD6–TD12 as documented. It is not a new runtime test;
the collaborator reports the existing flash/save gates passed at this commit.

### Safe coverage follow-up: T30 and T35 (2026-10-06)

T30 now toggles A's source to flash and checks B's known ROM signature before
changing B, restores A and checks its bank, then performs the inverse for B.
This tests both directions without relying on any initial flash contents. A
pathological flash image containing the exact 16-byte ROM signature at the
mapped offset could still mask source coupling; the result is consequently
understood as an isolation check with that small theoretical collision case.

T35 now follows Iceboy's Net de Get `is_sector0_protected()` sequence: keep flash
write protection enabled, issue `$AA/$55/$A0`, sample the raw status byte (bit
1 indicates sector-0 protection), and immediately use `Flash_Reset`. It never
loads program-buffer data or repeats a buffer slot, the documented programming
trigger. This is a read-only INFO observation; no protection command or
persistent flash operation is issued. The status meaning/procedure is
cartridge-specific research, not a first-party Macronix datasheet. The mGBA
source at `4c8066be4` maps `$A0` to status mode and returns ready/protection
bits, but this source inspection does not establish physical-cart behavior.

Only the default static ROM checks (`make` and `make verify`) were run after
this change. No emulator runtime, destructive build, fixture, or hardware test
was run in this follow-up.

### Net de Get custom catalog integration report (2026-10-06)

The REON server task reports that the opt-in per-user custom Net de Get catalog,
authenticated download route, and eligibility-gated charging were implemented
on branch `feature/net-de-get-custom-games` and pushed to GitHub `home` as
`c83087d`. PHP 8.5 lint and an offline fixture reportedly passed, including
opt-out with no download/charge and byte-for-byte comparison of a synthetic
response body. No deployment was reported.

The available PAD TEST fixture (`G001`, 168 bytes) is raw flash payload, not an
HTTP wrapper. The wrapper format (header/chunks/footer/padding) and natural
catalog recognition remain unverified against a real host capture. Until such
evidence is available, do not treat the synthetic fixture as proof of the
production wire format. This is a report from the related REON task, not an
independent test performed in this MBC6 Test ROM checkout.

### T30/T35 and full fixture regression at mGBA `4c8066be4` (2026-10-06)

The updated ROM (build ID `411BA0B+`, uncommitted shared checkout) was built
and statically verified in separate default and fixture directories under
`/tmp/mbc6-runtime-20261006`. The mGBA core exported
`0.11-feature/mbc6-complete-9338-4c8066be4` and full Git commit
`4c8066be47ff2881c70974280297e04227965c4f`. The fresh Linux shared-library build
was supplied by the collaborating mGBA task; the runner linked directly to
`/tmp/mgba-mbc6-head-linux`, and the library hash was unchanged before/after.
The older `/tmp/mgba-test-podman-build` library was not used for these runs
because its embedded commit/version identified an earlier dirty build.

| Disposable run | Frames | PASS / FAIL / SKIP / INFO | T30 | T35 raw status | M6TS checksum | Runner exit |
|---|---:|---|---|---|---|---:|
| Default, sector-0 protection metadata 0 | 40,900 | 15 / 0 / 0 / 5 | PASS | `$80` (bit 1 clear), INFO | `$42`, valid | 0 |
| Default, sector-0 protection metadata 1 | 40,900 | 15 / 0 / 0 / 5 | PASS | `$82` (bit 1 set), INFO | `$42`, valid | 0 |
| Destructive fixture, TD6 marker present | 41,030 | 22 / 0 / 0 / 10 | PASS | `$80`, INFO | `$4E`, valid | 0 |
| Destructive fixture, TD6 marker absent | 41,030 | 21 / 0 / 1 / 10 | PASS | `$80`, INFO | `$4E`, valid | 0 |

All M6TS records were format 2, suite 3, with first-failure ID `$FF`. The
runner read observation/status addresses from each build's `.sym` file. In
both default runs the complete `0x100101`-byte `.sav.flash` was byte-identical
to its seed after unloading/syncing, including the protection metadata. This
checks that the T35 probe did not change persistent flash in these emulator
runs; it does not independently establish hardware safety or protection state.

TD6 passed with the marker and skipped without it. Persisted hidden-map bytes
were 128 `$10` bytes followed by 128 `$80` bytes after the marker run, and the
seeded hidden map was unchanged in the no-marker run. TD10 observed `$C2/$81`
in both directions. TD11 observed busy `$00/$00`, then ready `$80/$80` through
A/B for program and chip erase; TD6 had the same busy/ready pairs. TD12 read
`$A5/$5A/$A5/$5A` at its four edge offsets. These are specific emulator-fixture
observations; cross-window timing/status and DQ4 remain unresolved hardware
questions. No new emulator bug appeared in this matrix.

SHA-256 identifiers:

- Default ROM: `60c5e5cb53c0efca2939c092fab835efbe336a4cd1049465ca5c0073007d0cd0`
- Fixture ROM (both destructive and mGBA fixture flags): `8d38097e24beeff657f6cd9c87f683f9bb120dfc5853a66c7d972f59412fdd10`
- `libmgba.so.0.11.0`: `4f1f2c68084400eaa544131bdc3b6b807a7f688e7edd8baf83d2fcabffb43f9d`
- Temporary headless runner: `a7419c90007e521ad516951ac6896eaf5fb7d3948ce141a200397171ba262892`

Runner source, build logs, stdout logs, 21-byte M6TS blocks, status snapshots,
and initial/final sidecars are under `/tmp/mbc6-runtime-20261006`. All ROMs and
saves used by the runner were disposable `/tmp` copies. No physical cartridge,
valuable save, libmobile code, or GUI screenshot was involved. This result
validates execution against the identified Linux mGBA core; hardware remains
unvalidated.

### Collaborator report: natural Net de Get local integration (2026-10-06)

The collaborating mGBA task reports a complete local fixture route: original
Net de Get ROM, loopback HTTP catalog/body, original ROM flash writer, BOX2
launch, all eight PAD TEST inputs, exit, BOX1 relaunch, and persistence after
reopening a fresh core. Its source documentation reports that the first 8 KiB
matched the fixture payload and the rest of the flash array, hidden map and
protection metadata remained unchanged. This was not independently executed
in this Test ROM checkout; it is a report checked against mGBA's committed
`doc/MBC6_FLASH.md` and `tools/mbc6/README.md`.

The reusable local driver and documentation are present at mGBA commit
`358230c82773aec67dff2995eb77fbd84f8ea8a2`. At report time, the new commit's
Linux rebuild, 33-target CTest run and repeated integration/Test ROM runs were
still pending. The Test ROM results above remain explicitly attributed to
`4c8066be4` and library SHA-256
`4f1f2c68084400eaa544131bdc3b6b807a7f688e7edd8baf83d2fcabffb43f9d`;
committing a driver does not reattribute those earlier executions.

This advances the earlier synthetic-only catalog/download report for the
specific local fixture. Production deployment, arbitrary payload compatibility,
physical cartridge behavior and other platform builds remain unvalidated.

### Postcommit mGBA `358230c82` validation (2026-10-06)

The mGBA collaborator completed a new Linux build and reran the same Test ROM
artifacts after committing the portable integration driver. I checked its
stdout logs, the build/CTest summary, the current library hash, and the OMM
report `f468eb8c-52af-42f7-a6b1-d489cecfc732`; I did not launch these new runs
myself. This closes the pending postcommit validation noted above.

Both Test ROM logs identify `0.11-feature/mbc6-complete-9339-358230c82`, full
commit `358230c82773aec67dff2995eb77fbd84f8ea8a2`. The new library SHA-256 is
`ee5795ed0eee7e0c4bd724dd73c490011d74e50af7b7bc1fe48b1079f033a29e`.
The default ROM returned 15 PASS / 0 FAIL / 0 SKIP / 5 INFO, checksum `$42`;
the marker fixture returned 22 PASS / 0 FAIL / 0 SKIP / 10 INFO, checksum `$4E`.
Both checksums were valid, first-failure ID was `$FF`, T30 was PASS and T35
was INFO with raw `$80`. The collaborator reports runner exit 0 for both.
The logs are `/tmp/mbc6-runtime-20261006/postcommit-358230-default.log` and
`postcommit-358230-marker.log`. The ROM hashes remain the default/fixture
hashes recorded above; the protection=1 and no-marker runs above retain their
original `4c8066be4` provenance.

The build log `/tmp/mgba-mbc6-358230-linux-build.log` reports all 33 CTest
targets passed with Qt offscreen. The collaborator also reports that the
portable natural local integration and fresh-core reopening passed on this
new build. Both `/tmp/mgba-netdeget-local-scaagyaa/run.log` and
`reopened/run.log` print the new commit/version; the complete result/assertions
are recorded in mGBA's OMM report and committed integration documentation.
Only the Linux release was refreshed according to the collaborator. These
remain emulator/local-fixture results; production deployment, arbitrary
minigame compatibility and hardware validation are not established.


### Integrated offline install/execute/reopen fixture (2026-10-06)

Added an opt-in workflow in `src/tests_netdeget.asm`, centralized A-only
command helpers in `src/flash.asm`, and a reusable Linux headless runner in
`tools/run_mgba_offline.py` / `tools/mgba_offline_runner.c`. The procedure,
source qualification and separate M6OF ABI are in
[net-de-get-offline.md](net-de-get-offline.md). It requires both destructive
flags plus `ENABLE_NETDEGET_OFFLINE_FIXTURE=1` and the exact hidden-map marker
`M6OFFLINEFIXTURE`. The safe build contains none of the offline workflow.
This is original generated homebrew data, not distributed Net de Get content.

The workflow erases/checks sector 7, stages two 4 KiB WRAM buffers, programs
64 aligned pages into flash bank 112, checks every page and all 8 KiB through
A/B, compares 16-bit sums, executes a two-receipt RET payload, restores ROM
banks/sources A=2/B=3 and WRAM bank1, and verifies ROM signatures. A valid prior
completed record selects read/execute-only reopening. Polls are bounded and
raw busy/ready values remain observational. The post-ready single F0 follows
the host writer; failure recovery retains Iceboy's complete Flash_Reset.
The payload sum is a fixture sum, not Net de Get's header checksum algorithm.

Direct final precommit execution used normal ROM boot and joypad confirmation
against mGBA `0.11-feature/mbc6-complete-9339-358230c82`, commit
`358230c82773aec67dff2995eb77fbd84f8ea8a2`, Linux library SHA-256
`ee5795ed0eee7e0c4bd724dd73c490011d74e50af7b7bc1fe48b1079f033a29e`.
The Test ROM was built from the shared dirty `411BA0B+` checkout:

- ROM: `3dbd500572964f013ec1f59e3cece672ac78bdbfad6680b0bd58c6d5a4773015`.
- Symbols: `b9257fe8c7aadf8f485a47b82389cd298460903fbccff51d0b022b1e269b16e6`.
- Payload: `e01aa1697dd91be764bee8a40862ca400b41a1a71799dde3ecd2815efa581390`.
- Installed/reopened full flash sidecar:
  `be1047b6a1257e84dd3959b8fe2710951c564e553e92a18d996abb4d221f5b43`.

| Case | Frames | Offline verdict | Written pages | Evidence |
|---|---:|---|---:|---|
| Install | 1184 | PASS, phase7/mode1 | 64 | Full payload and erased sector tail match; seven other sectors, hidden map and protection metadata unchanged; receipts A6/5A, both sums62057, ROM signatures restored. |
| Fresh-core reopen | 1130 | PASS, phase7/mode2 | 0 | Same payload execution and full byte-identical sidecar. |
| SELECT cancel | 1130 | NOT RUN in transient WRAM/UI | 0 | Poisoned transient result initialized; done0/page3; previous SRAM M6OF receipt and complete sidecar preserved. |
| Invalid prior record | 1130 | FAIL, phase2/mode2 | 0 | Prior phase6 with a valid recalculated checksum rejected; full installed sidecar unchanged. |
| No hidden marker | 1130 | SKIP, phase1/mode0 | 0 | No erase/program/execute; entire initial sidecar unchanged. |
| Corrupted reopen | 1130 | FAIL, phase5/mode2 | 0 | Offset0100 expected5B/actual5A; no retry, repair or payload execution; entire injected sidecar unchanged. |

All six runner processes exited0 and all **56 assertions passed**. Each safe
M6TS block retained format2/suite3, 15 PASS / 0 FAIL / 0 SKIP / 5 INFO,
checksum42. WRAM bank readback was1 in all cases. The persisted PASS receipt
in the cancel case belongs to the previous run; the current session's WRAM
result is NOT RUN. Evidence is `/tmp/mbc6-offline-lbtj3eau/report.json` and its
ROM/symbol snapshots, logs, M6TS/M6OF/WRAM records and complete flash/SRAM files.
The runner subagent independently passed the same 56 checks in
`/tmp/mbc6-offline-ig86n0yk/report.json`.

Read-only review found and corrected two issues before this final run:
initialize the offline result before confirmation to prevent a stale PASS on
cancel, and validate prior receipt semantics (phase/mode/pages/receipts,
restoration/marker, reserved bytes and sums) beyond its checksum. The mGBA
collaborator's earlier cross-check passed the initial ROM revision
`8f5717cd7866afc58dd10b51f26b274e25d25217618f33666592fdb08e6ddff1`
in `/tmp/mbc6-offline-9m__e00v/report.json`; that result predates these fixes
and must not be presented as a check of the final revision.

Build/static verification passed for safe, ordinary fixture and offline
configurations. At the same build ID, safe ROM SHA60c5e5cb... and ordinary
fixture SHA8d38097e... remain the exact artifacts recorded above. A commit's
new diagnostic build ID changes rebuilt ROM hashes; use the runner's input
hashes for any later checkpoint run. No new mGBA core defect was observed.
No hardware, physical power-cycle, network installation, original-game checksum
or arbitrary minigame compatibility is established by this fixture.
