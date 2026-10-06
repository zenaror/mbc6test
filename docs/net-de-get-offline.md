# Offline Net de Get flash workflow fixture

This optional fixture exercises a local install/readback/execute/reopen cycle
with an original homebrew payload. It needs neither the Net de Get ROM nor a
server, REON, a Mobile Adapter or proprietary assets. It is a disposable mGBA
integration test, not physical cartridge validation.

## Build and run

All three flags are required. The ordinary destructive tests are replaced by
this workflow so that reopening cannot erase the installed payload first.

```sh
make BUILD_DIR=/tmp/mbc6-offline-build \
  ENABLE_DESTRUCTIVE_FLASH_TESTS=1 ENABLE_MGBA_FLASH_FIXTURE_TESTS=1 \
  ENABLE_NETDEGET_OFFLINE_FIXTURE=1
make verify BUILD_DIR=/tmp/mbc6-offline-build \
  ENABLE_DESTRUCTIVE_FLASH_TESTS=1 ENABLE_MGBA_FLASH_FIXTURE_TESTS=1 \
  ENABLE_NETDEGET_OFFLINE_FIXTURE=1
python3 tools/run_mgba_offline.py \
  --rom /tmp/mbc6-offline-build/mbc6-test.gbc \
  --sym /tmp/mbc6-offline-build/mbc6-test.sym \
  --mgba-source /path/to/mgba \
  --mgba-library /path/to/libmgba.so
```

The Linux host runner creates a new directory under `/tmp`, compiles a small
mCore harness against the supplied mGBA headers/library and preserves evidence
there. Read its report for exact emulator version/commit and artifact hashes.
It starts the ROM normally and confirms with A+B+Start; it does not force PC
into a test routine. A fresh harness process is used for reopening. The default
build and the older destructive fixture build retain their previous code;
with the same diagnostic build ID, their ROM bytes are unchanged.

## Procedure and guards

1. Run the safe suite, then require the usual deliberate button confirmation.
2. Read the hidden-map offsets `$F0-$FF` and require exactly
   `M6OFFLINEFIXTURE` before any erase/program command. Without it, report SKIP
   and leave the complete flash sidecar unchanged. The marker is a fixture
   guard; it cannot make a physical cart safe to erase.
3. If no `M6OF` record exists, erase sector 7 and verify all its 128 KiB as
   `$FF`. Generate an 8 KiB payload in two successive 4 KiB buffers at
   WRAM bank 2 `$D000-$DFFF`. The deterministic byte at global offset `i` is
   `low(i) XOR high(i) XOR $5A`, except for the first bytes, which contain
   original code that stores receipts `$A6/$5A` in WRAM and returns.
4. Program bank 112 (`$70`, flash linear `$E0000`) through window A in
   64 aligned 128-byte pages. Unlock entirely through A (selectors 2, 1, 2),
   issue `$A0`, map the destination, raise WE, copy the page and repeat its
   last slot with zero as a separate trigger. Poll DQ7 with a software bound.
   After ready, issue the host-style single `$F0`, lower WE, then check all
   page bytes. A timeout uses the full Iceboy `Flash_Reset` procedure.
5. Read every payload byte through A and B; compare against regenerated WRAM
   data and compare the 16-bit sums. The sums supplement full byte comparison;
   they are not the original Net de Get game's header/checksum contract.
6. Call `$4000` to execute the installed payload and check its two receipts.
   Return to fixed ROM, lower WE, restore ROM source/banks A=2 and B=3 and
   WRAM bank 1, then verify both 16-byte ROM signatures. The payload does not
   change mapper registers, and all mapping code executes in ROM0.
7. Write a separate `M6OF` result. On the next run, a valid prior PASS record
   selects mode 2: regenerate, read/compare, checksum and execute, with no
   erase/program. A malformed record with `M6OF` magic or a failed prior run
   produces FAIL rather than an automatic destructive retry. For a deliberate
   new install, create a new disposable fixture.

The runner compares the complete persisted sidecar after unloading the core:
the other seven sectors, hidden map and protection metadata must remain as
seeded; the unused part of sector 7 must be erased; the payload must match
exactly. Reopening must leave all flash bytes unchanged. Negative cases cover
missing marker and corruption at payload offset `$0100`: corruption must FAIL
without retrying or repairing flash. A prior record with an invalid completion
phase but a recomputed valid checksum must also FAIL before writing flash.
SELECT cancellation is checked after poisoning the transient WRAM result:
the UI must show NOT RUN, `wOfflineDone` must stay zero, and both flash and
the previous SRAM M6OF receipt remain unchanged. The saved receipt describes
the previous completed run, not the cancelled session. SRAM output may
otherwise change on reopening.

## Result annex (`M6OF`, format 1)

SRAM bank 7, window B `$BF20-$BF3F`, raw SRAM file offset `$7F20`, 32 bytes.
The standard 21-byte [M6TS result](result-format.md) at `$BF00` still describes
only the safe suite in this build. Its PASS count does not imply this workflow
passed. The offline result appears as its own first UI page; A cycles pages.

| Offset | Bytes | Meaning |
|---:|---:|---|
| 0 | 4 | ASCII `M6OF` |
| 4 | 1 | Format version 1 |
| 5 | 1 | Status: 1 PASS, 2 FAIL, 3 SKIP; UI zero means not run |
| 6 | 1 | Phase: 1 marker, 2 resume, 3 erase, 4 program, 5 verify, 6 execute, 7 done |
| 7 | 1 | Mode: 1 install, 2 reopen; zero before selection |
| 8 | 1 | Completed program operations: 64 for install, 0 for reopen |
| 9 | 1 | First raw status sample after the last page trigger, observational |
| 10 | 1 | Last polled page status byte, observational |
| 11 | 2 | Payload execution receipts `$A6/$5A` on success |
| 13 | 2 | Actual payload sum, little endian |
| 15 | 2 | Expected payload sum, little endian |
| 17 | 2 | First mismatching bank-local offset, little endian |
| 19 | 1 | Expected byte at a readback mismatch |
| 20 | 1 | Actual byte at a readback mismatch |
| 21 | 1 | ROM signatures verified after successful execution/restoration |
| 22 | 1 | Hidden fixture marker matched |
| 23 | 8 | Reserved, zero |
| 31 | 1 | Sum of bytes 0–30 modulo 256 |

Offsets 17–20 are meaningful for readback failures; phase identifies other
failures. Cleanup restores the default mappings even on FAIL/SKIP; offset 21
is zero when the success-path signature verification was not reached.

## Evidence scope

The page writer follows the static A-window sequence identified in Net de Get
ROM0 `$1568` and its 4 KiB WRAM caller; the A-only unlock helper is at `$164D`.
See [mbc6-reference.md](mbc6-reference.md) for the investigated ROM hash,
routine map, source hierarchy and the reset distinction. The fixture uses
its own generation, full readback and simple payload, rather than reproducing
the original game, decompressor, catalog, UI or networking code.

Status latency, opposite-window status visibility and undocumented DQ4/DQ5
semantics remain observational. A/B full array readback here validates this
emulator fixture; it does not settle disputed cross-window command/status
behavior on silicon. Reopening validates the emulator's persistence format,
not a cart power-cycle or compatibility with arbitrary downloaded minigames.
Record execution results with hashes and versions in [mbc6-notes.md](mbc6-notes.md).
