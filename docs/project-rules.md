# Project rules — MBC6 Test ROM

This file holds the project's full technical rules. Until 2026-10-04 they
lived in `CLAUDE.md`, which was removed at the project operator's request.
The text below is unchanged except for this note, the spelled-out name of the iceboy
reference, the repository-structure listing, and the shared-memory section
at the end. `AGENTS.md` is the short working guide for
agents and points here.

## Project mission

This repository builds an open-source **Game Boy Color (CGB-only)** test ROM for validating MBC6 mapper implementations.

The primary consumer is emulator development (initially BGB), but the suite must remain emulator-agnostic and useful to other emulators and compatible hardware.

This is a hardware-conformance project. Correctness, determinism, and traceability to documented MBC6 behavior are more important than visual polish.

The target platform is **CGB only**. Do not spend implementation effort on DMG, MGB, SGB, or dual-mode compatibility. The ROM must declare itself as CGB-only in the cartridge header.

## Required references

See [`mbc6-reference.md`](mbc6-reference.md) for a consolidated, reusable
technical overview of the MBC6 mapper and Net de Get flash. This file remains
the source of project-specific implementation and testing rules.

### MBC6-specific references

Before changing mapper or flash behavior, consult the relevant source:

- Pan Docs — MBC6: https://gbdev.io/pandocs/MBC6.html
- Macronix — MX29F800C T/B datasheet (8-Mbit NOR; related part, not the exact MX29F008TC-14 used in Net de Get): https://www.macronix.com/Lists/Datasheet/Attachments/8539/MX29F800C%20T-B%2C%205V%2C%208Mb%2C%20v1.3.pdf
- GBDev MBC6 research thread: https://gbdev.gg8.se/forums/viewtopic.php?id=544
- iceboy / Michael Singer — Nintendo Power GB Memory (NP GB Memory) and Net de Get flash research: https://iceboy.a-singer.de/doc/np_gb_memory.html
- ZoomTen `mbc30test`: https://github.com/ZoomTen/mbc30test
- EricKirschenmann / HyperHacker `MBC3-Tester-gb`: https://github.com/EricKirschenmann/MBC3-Tester-gb

### Game Boy Color / RGBDS programming references

Use these references for general CGB programming, CPU behavior, memory layout, cartridge headers, and RGBDS syntax/tooling:

- Pan Docs — main documentation: https://gbdev.io/pandocs/
- Pan Docs — CGB registers / CGB mode: https://gbdev.io/pandocs/CGB_Registers.html
- Pan Docs — cartridge header: https://gbdev.io/pandocs/The_Cartridge_Header.html
- GB ASM Tutorial: https://gbdev.io/gb-asm-tutorial/
- RGBDS documentation: https://rgbds.gbdev.io/docs/master/
- gbdev `hardware.inc`: https://github.com/gbdev/hardware.inc
- Gekkio — Game Boy: Complete Technical Reference: https://gekkio.fi/files/gb-docs/gbctr.pdf
- Nintendo — Game Boy Programming Manual, Version 1.1 (1999): https://dn760008.eu.archive.org/0/items/GameBoyProgManVer1.1/GameBoyProgManVer1.1.pdf

The Nintendo Game Boy Programming Manual v1.1 is an important historical first-party programming reference and includes Game Boy Color programming material. Use it for official-era architecture, terminology, display/memory guidance, and CGB programming conventions. Do not treat it as a source for undocumented MBC6 flash behavior that it does not specify.

Source precedence:

1. current Pan Docs for explicitly specified MBC6 and CGB behavior;
2. an official Macronix datasheet for the exact part, when available; the linked MX29F800C T/B datasheet is first-party but only a related 8-Mbit device and must not be treated as exact-part proof;
3. iceboy documentation for detailed, cartridge-specific MX29F008TC/ATC observations and procedures;
4. GBDev MBC6 research observations for unresolved/experimental mapper behavior;
5. Gekkio's technical reference and the Nintendo Game Boy Programming Manual v1.1 for general hardware/CGB behavior;
6. current RGBDS documentation for assembler/linker/toolchain behavior;
7. GB ASM Tutorial and `hardware.inc` for implementation conventions;
8. the MBC3/MBC30 test ROMs only as test-ROM design inspiration.

Never convert an uncertain observation into a normative PASS/FAIL expectation. Existing emulator behavior and existing test ROMs are not hardware specifications by themselves.

## Toolchain

Use RGBDS and LR35902 assembly.

Target RGBDS 1.0.x. RGBDS 1.0.3 is a known-good baseline for this project specification.

Expected commands/tools:

- `rgbasm`
- `rgblink`
- `rgbfix`
- `python3` for host-side deterministic generation or ROM verification only
- `make`

Do not replace the mapper core with GBDK/C abstractions. Direct MBC6 accesses must remain easy to audit.

## Mandatory build workflow

After modifying source, linker layout, generated bank data, headers, or build scripts, run:

```sh
make
make verify
```

If layout/header generation changed materially, prefer:

```sh
make clean
make
make verify
```

Before considering a task complete, `make verify` must pass.

`make test` should mean build + static verification unless an actual emulator test runner has been implemented. Never claim runtime MBC6 correctness based only on successful compilation.

If RGBDS is not installed, report the missing dependency clearly. Do not rewrite the project around another toolchain merely to avoid installing RGBDS.

## Required ROM format

The produced ROM must be exactly 1 MiB (1,048,576 bytes).

Required header values:

- `$0143 = $C0` — **CGB-only** cartridge
- `$0147 = $20` — MBC6
- `$0148 = $05` — 1 MiB ROM
- `$0149 = $03` — 32 KiB SRAM

This project is intentionally CGB-only. Do not change `$0143` to `$80` for dual DMG/CGB compatibility. DMG, MGB, SGB, and monochrome compatibility mode are outside the test target. CGB-specific registers/features may be used when useful, although the mapper tests should avoid unrelated dependencies that make failures harder to diagnose. Keep the CPU in normal-speed mode by default unless a dedicated, documented timing test explicitly requires CGB double-speed mode.

The host-side verifier must validate the header and image size.

## MBC6 memory model

Treat these as first-class architectural facts:

```text
$0000-$3FFF  fixed ROM, first 16 KiB
$4000-$5FFF  ROM/Flash window A, 8 KiB
$6000-$7FFF  ROM/Flash window B, 8 KiB
$A000-$AFFF  SRAM window A, 4 KiB
$B000-$BFFF  SRAM window B, 4 KiB
```

Registers:

```text
$0000-$03FF  SRAM enable
$0400-$07FF  SRAM Bank A
$0800-$0BFF  SRAM Bank B
$0C00-$0FFF  Flash Enable
$1000        Flash Write Enable / WP control
$2000-$27FF  ROM/Flash Bank A number
$2800-$2FFF  Bank A source select: $00 ROM, $08 flash
$3000-$37FF  ROM/Flash Bank B number
$3800-$3FFF  Bank B source select: $00 ROM, $08 flash
```

MBC6 ROM bank numbers are 8 KiB units. MBC6 SRAM bank numbers are 4 KiB units.

Bank 0 is valid in the switchable ROM windows.

## Fixed-ROM safety rule

Any routine that writes MBC6 ROM/Flash mapping registers must execute from `$0000-$3FFF`.

Do not place mapper-changing code in `$4000-$7FFF`.

Keep core mapper helpers, flash helpers, assertions, dispatcher, and failure handling in fixed ROM.

If ROM0 space is tight, simplify UI/assets before violating this rule.

## ROM bank layout

The 1 MiB image represents 128 physical MBC6 8 KiB banks (`$00-$7F`). RGBDS uses 16 KiB linker banks, so each RGBDS bank contains two MBC6 sub-banks.

Every 8 KiB physical bank must contain a unique deterministic signature at the same local offset, preferably `$1FF0` within the sub-bank.

The signature should include at least:

- a fixed magic;
- the 8 KiB bank number;
- its complement;
- additional sentinels/check bytes.

The signature for all 128 physical banks must be verified from the final `.gb` file by `tools/verify_rom.py`.

Do not rely on linker bank numbers alone when reasoning about MBC6 bank numbers.

## Power-on state

The safe test suite should capture the switchable ROM windows before writing any MBC6 register.

The documented reset/power-up state used by the iceboy MBC6 procedures is:

```text
SRAM disabled
Flash Enable       = 0
Flash Write Enable = 0
Bank A source      = ROM
Bank B source      = ROM
SRAM Bank A        = 0
SRAM Bank B        = 1
ROM Bank A         = 2
ROM Bank B         = 3
```

Where observable, initial `$4000-$5FFF` and `$6000-$7FFF` should therefore resolve to physical 8 KiB ROM banks 2 and 3.

Capture before UI initialization code has any opportunity to write MBC registers.

## Required safe tests

The default build must contain no flash erase/program/protect/unprotect path.

At minimum keep tests for:

1. startup/power-on state;
2. full Bank A ROM sweep `$00-$7F`;
3. full Bank B ROM sweep `$00-$7F`;
4. Bank A/B independence;
5. explicit ROM bank 0 mapping;
6. 8 KiB ROM window boundaries;
7. SRAM enable/disable behavior without assuming undocumented open-bus values;
8. SRAM Bank A sweep 0-7;
9. SRAM Bank B sweep 0-7;
10. SRAM A/B independence;
11. 4 KiB SRAM granularity;
12. independent ROM-vs-flash source selection;
13. JEDEC ID through Bank A;
14. JEDEC ID through Bank B;
15. flash `$F0` reset/exit behavior;
16. hidden 256-byte region read as INFO, not an expected content value;
17. non-destructive sector-0 protection observation if supportable from documentation.

Expected Net de Get flash JEDEC ID:

```text
manufacturer = $C2
device       = $81
```

## Test statuses

Use exactly these semantic result classes:

- `PASS` — documented required behavior matched
- `FAIL` — documented required behavior did not match
- `SKIP` — test cannot safely/meaningfully run
- `INFO` — observation with no normative expected value

Unknown behavior must not influence the compatibility score.

A failure record should preserve as much of the following as relevant:

- test ID;
- address/register;
- selected bank;
- expected value;
- actual value.

Prefer a precise first-failure report over a generic “MBC6 FAIL”.

## Flash rules

The MBC6 cartridge uses a Macronix MX29F008TC-14 1 MiB flash.

Important constraints:

- JEDEC ID for Net de Get is `$C2/$81`.
- Flash sectors are 128 KiB; there are 8 sectors.
- A hidden 256-byte region exists.
- program operations use 128-byte aligned buffered writes.
- status bit 7 indicates completion/ready.
- Net de Get appears to check status bit 4 as a timeout flag (Dan Docs
  reverse-engineering); iceboy records bits 5–4 as driven but unknown, observed
  low. Do not make bit 4 a normative hardware requirement without better
  evidence.
- Flash Write Enable / WP protects sector 0 and the hidden region, not sectors 1-7.

Do not model `$1000` as a generic global write-enable bit.

Centralize command sequences in `src/flash.asm` or equivalent. Do not duplicate raw JEDEC command sequences throughout tests.

Any flash status polling loop must have a software timeout. Never hang forever on an incomplete emulator implementation.

On timeout:

1. record FAIL when the expected behavior is normative;
2. save the last status byte;
3. issue `$F0` reset if safe;
4. continue testing where possible.

## Destructive flash policy

Destructive flash tests must be compile-time disabled by default.

Use a symbol such as:

```text
ENABLE_DESTRUCTIVE_FLASH_TESTS = 0
```

When disabled, no persistent erase/program/protect/unprotect operation may be
triggerable from the default UI. T35 is the documented read-only exception:
it enters program/status mode only to sample protection bit 1, writes no buffer
payload, never repeats a buffer slot to trigger programming, and immediately
uses `Flash_Reset` to abort. Keep this sequence centralized in `src/flash.asm`.

When enabled:

- show a strong warning;
- require deliberate multi-button confirmation;
- state that cartridge flash data may be permanently destroyed;
- assume disposable emulator/flash state, not that arbitrary original data can be restored.

A 128 KiB sector cannot be fully backed up into 32 KiB SRAM, so do not claim automatic rollback of arbitrary real-cartridge flash contents.

### Disposable mGBA flash fixtures

TD6 hidden-map erase/program and the additional cross-window/status/page-edge
observations TD10–TD12 are compiled only when both
`ENABLE_DESTRUCTIVE_FLASH_TESTS=1` and `ENABLE_MGBA_FLASH_FIXTURE_TESTS=1` are
set. TD11 issues a whole-chip erase; iceboy documents the mass-erase sequence,
but the ROM keeps it fixture-only. TD6 first requires the exact 16-byte
hidden-map marker `M6TD6FIXTUREONLY` at offsets `$F0-$FF`; without it, TD6
records SKIP before issuing any hidden-map command. The marker is a fixture
gate, not a hardware detector. The second flag is a build-time fixture fence:
use a disposable ROM copy and save directory in mGBA, never a physical
cartridge or valuable save. The default and ordinary destructive builds omit
the hidden-map/whole-chip helpers; ordinary destructive TD6 is an explicit
SKIP. TD10–TD12 remain INFO observations where source does not specify
cross-window behavior.

Prefer sector 7 for destructive fixture tests by convention, but still label it destructive.

## Undefined / experimental behavior

The historical MBC6 research thread mentions unresolved observations such as:

- a high bank-number bit apparently unmapping ROM in some tests;
- `Net de Get` writing `$C6` to bank source/type registers for an unknown reason.

Treat these only as experimental `INFO` tests unless authoritative documentation is updated.

Do not add a required emulator behavior based solely on those observations.

## SRAM testing

SRAM tests may overwrite the test ROM's save RAM.

Use deterministic patterns unique to each 4 KiB bank and multiple offsets per bank.

Verify persistence across bank switches during the same run.

Do not use a machine-readable result block until the SRAM banking tests have finished, or isolate its region so it cannot mask failures.

## UI principles

Keep the UI simple.

Required functionality:

- run all safe tests;
- run categories/individual tests;
- final summary;
- detailed first failure;
- INFO/experimental page;
- destructive menu only in destructive builds.

Do not use color as the only status indicator.

Do not spend fixed-ROM budget on decorative animation.

## Host-side verification

`tools/verify_rom.py` must fail non-zero when any static invariant is broken.

Verify at least:

- output exists;
- output is exactly 1 MiB;
- CGB flag is `$C0`;
- cartridge type is `$20`;
- ROM size byte is `$05`;
- RAM size byte is `$03`;
- header checksum is correct;
- global checksum is correct if intentionally maintained;
- all 128 8 KiB bank signatures are present at the expected physical offsets;
- each signature contains the correct bank ID and check bytes;
- bank signatures are unique.

Prefer verifying the final linked/fixed ROM rather than trusting source macros.

## Suggested repository structure

```text
.
├── AGENTS.md
├── Makefile
├── README.md
├── docs/
│   ├── project-rules.md
│   ├── mbc6-notes.md
│   ├── test-matrix.md
│   └── result-format.md
├── include/
│   ├── hardware.inc
│   ├── mbc6.inc
│   └── tests.inc
├── src/
│   ├── main.asm
│   ├── header.asm
│   ├── ui.asm
│   ├── mbc6.asm
│   ├── flash.asm
│   ├── tests_rom.asm
│   ├── tests_ram.asm
│   ├── tests_flash.asm
│   └── bank_data.asm
└── tools/
    └── verify_rom.py
```

Use a different layout only if it makes mapper code more auditable.

## Documentation discipline

Maintain `docs/test-matrix.md`.

Every normative test must identify:

- test ID;
- behavior;
- safe/destructive classification;
- expected result;
- authoritative source;
- implementation status.

When writing a low-level sequence whose correctness is non-obvious, add a concise source-oriented comment.

Do not copy long passages from external documentation.

## No proprietary ROM dependency

Never add or require:

- `Net de Get` ROM data;
- extracted commercial graphics;
- commercial save data;
- downloaded minigame payloads;
- copyrighted Nintendo assets beyond what is technically required for a standard bootable GB header and can be generated/handled by the normal toolchain.

All test data must be generated by this project.

## Scope control

The supported execution target is CGB mode only. DMG, MGB, SGB, and dual-mode compatibility are out of scope.

Do not add unrelated Game Boy CPU/PPU/APU tests.

This is an MBC6 test ROM.

A helper may test general memory behavior only when necessary to isolate an MBC6 result.

## Definition of done for a change

A mapper/test change is not done until:

1. source is internally consistent;
2. `make` succeeds;
3. `make verify` succeeds;
4. new normative behavior is reflected in `docs/test-matrix.md`;
5. no default code path became destructive;
6. uncertainty is labeled as INFO/SKIP rather than guessed;
7. the final response states what runtime behavior still needs to be checked in BGB/other emulators or hardware.

Runtime results from the user or emulator developer are evidence to iterate on the tests; do not rewrite expected hardware behavior merely to make a particular emulator pass.

## Fixture offline integrada

`ENABLE_NETDEGET_OFFLINE_FIXTURE=1` exige as duas flags destrutivas e seleciona
uma sequência própria no lugar de TD1-TD12, preservando o payload para reopen.
Exige o marcador hidden-map `M6OFFLINEFIXTURE` antes de erase/program. Use só
arquivos descartáveis do mGBA em `/tmp`. A sequência, o runner e o anexo M6OF
estão em [net-de-get-offline.md](net-de-get-offline.md). Não muda a ABI M6TS
nem transforma timing/status observado no emulador em regra de hardware.

## Exploratory erase-bank latch fixture

The exploratory `ENABLE_FLASH_LATCH_FIXTURE=1` requires both destructive
fixture flags, excludes the offline workflow, and uses its own M6FL annex.
It requires the hidden marker `M6LATCHFIXTUREON` before sector7 erase. Use only
disposable `/tmp` mGBA copies. Raw post-erase/enable-cycle reads are INFO;
do not invent a hardware expectation. See [flash-latch-fixture.md](flash-latch-fixture.md).

## Memória compartilhada OMM

Consulte [OMM.md](../OMM.md) e pesquise na OMM pelo MCP, no escopo `mbc6test`, antes de repetir uma investigação. Os dados da OMM ficam só no `ai-omm-backup`, nunca neste repositório. Ao guardar uma descoberta útil, registre sua origem, versão e evidência. Ao encerrar uma sessão, atualize o handoff da OMM com o estado e a próxima ação.

As anotações do OMM não substituem a hierarquia de fontes deste arquivo. Uma observação de emulador ou uma hipótese experimental não vira requisito normativo sem evidência apropriada. A aprovação em `make verify` demonstra invariantes estáticos da ROM; não prova funcionamento do mapper em hardware.
