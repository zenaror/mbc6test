# Flash erase-bank latch / enable-cycle observation

Exploratory fixture for the reported Net de Get MOVE/DELETE failure. This
fixture records raw reads; it does **not** establish that the failure is caused
by the mapper, prescribe a latch lifetime, or change the released Test ROM.
The investigation lives on `codex/flash-enable-latch-observation`.

## Evidence and scope

[Dan Docs, MBC6 Flash Operation](https://shonumi.github.io/dandocs.html#ndg)
describes the bank selected at sector erase as remembered in the operation
window until a new command. Its text does not define what a flash enable
cycle does to that remembered bank. [Iceboy's cartridge research](https://iceboy.a-singer.de/doc/np_gb_memory.html)
and Dan Docs also differ on aspects of erase/status handling; neither the
current emulator nor this fixture is authority for unresolved silicon behavior.

The mGBA owner reported a natural two-games/same-box MOVE then DELETE failure
and a later download where flash `$E2000` received new data while `$E0000`
remained erased. Those are investigation leads from that chat, not executions
reproduced here. Auditors are tracing erase B, `$F0`, flash disable/re-enable,
bank/source remapping and reads at `$6005/$6044` before the next `$A0` opcode.
This fixture isolates a related register sequence without distributing the
original ROM, modifying the emulator core, or using hardware/network services.

## Build and run

```sh
make BUILD_DIR=/tmp/mbc6-latch-build \
  ENABLE_DESTRUCTIVE_FLASH_TESTS=1 ENABLE_MGBA_FLASH_FIXTURE_TESTS=1 \
  ENABLE_FLASH_LATCH_FIXTURE=1
make verify BUILD_DIR=/tmp/mbc6-latch-build \
  ENABLE_DESTRUCTIVE_FLASH_TESTS=1 ENABLE_MGBA_FLASH_FIXTURE_TESTS=1 \
  ENABLE_FLASH_LATCH_FIXTURE=1
python3 tools/run_mgba_latch.py \
  --rom /tmp/mbc6-latch-build/mbc6-test.gbc \
  --sym /tmp/mbc6-latch-build/mbc6-test.sym \
  --mgba-source /path/to/mgba \
  --mgba-library /path/to/libmgba.so
```

The third flag requires both destructive fixture flags and is mutually
exclusive with `ENABLE_NETDEGET_OFFLINE_FIXTURE`. It replaces TD1-TD12 with
this observation. The default ROM and released artifacts are not modified.
The host runner uses fresh `/tmp/mbc6-latch-*` copies, normal ROM boot, joypad
confirmation and a bounded completion wait. It records hashes, embedded core
version and full SRAM/flash snapshots. No PC redirection is used.

## Procedure

Before any erase, require the 16-byte hidden-map marker `M6LATCHFIXTUREON`
at `$F0-$FF`. Without it, return SKIP and verify the complete flash sidecar is
unchanged. The marker is a fixture guard, not a hardware detector. SELECT at
confirmation cancels without performing this observation.

The fixture seeds bank96 (sector6, linear `$C0000`) with `$A5` at local `$0005`
and `$C3` at `$0044`. Sector7 is seeded with `$37` throughout. A and B initially
map bank96; record both offset pairs as the baseline. A bank outside sector7
is necessary because erasing that entire sector would otherwise erase both
the target and the comparison bank.

1. Issue the B-only unlock/sector-erase sequence, targeting bank112 (sector7).
   Sample status through B `$6000`, poll ready DQ7 with a software bound.
2. After ready, write a single `$F0` at B `$6000` and lower WE. Change only
   bank/source mapping to bank96 in both windows. Record B `$6005/$6044`
   and A `$4005/$4044`. Do not use `Flash_Reset` or an enable helper between
   the erase and this sample: those would contaminate the independent variable.
3. Perform `WE=1; enable=0; WE=0; WE=1; enable=1; WE=0`, then reselect bank96
   and flash source in both windows. Record the same four addresses. No new
   chip opcode occurs between steps2 and3. The measured variable is this
   complete register cycle, not the isolated effect of `$0C00` or `$1000`.
4. As a separate control, issue a B-only `$90` autoselect opcode without
   an enable cycle, then `$F0`; map bank96 and record B's offset pair again.
5. Restore ROM source/banks A=2/B=3, WE=0 and WRAM bank1. Write the result
   annex and the ordinary safe-suite M6TS record.

No after-erase read is scored against a guessed value. A completed sequence
is INFO whether it returns erased bytes, bank96 sentinels or another raw value.
A polling timeout is an operational FAIL, with the raw status/phase retained;
recovery uses the full Iceboy `Flash_Reset` only after aborting the sequence.

The host runner asserts fixture integrity: baseline sentinels, bounded
completion, record/checksum, full sector7 erased, and every byte of the other
seven sectors, hidden map and protection metadata preserved. These setup and
persistence checks are distinct from the unresolved read observations. It
reports whether each raw read matches the other-bank seed or erased data,
without asserting either classification as correct hardware behavior.

## M6FL annex (format1)

32 bytes at SRAM bank7, window B `$BF60-$BF7F`, raw file offset `$7F60`.
This does not overlap M6TS at `$BF00` or M6OF at `$BF20`. Safe-suite scores
remain independent; this build displays a fourth `FLASH LATCH INFO` page
first, with baseline/continuous/cycled/new-command B pairs.

| Offset | Meaning |
|---:|---|
| 0–3 | ASCII `M6FL` |
| 4 | Format1 |
| 5 | Outcome: 3 INFO, 2 SKIP, 1 operational FAIL; UI0 NOT RUN |
| 6 | Phase: 1 marker, 2 baseline, 3 erase/poll, 4 continuous, 5 cycle, 6 opcode control, 7 done |
| 7–8 | Erase bank112 and other bank96 |
| 9–12 | Baseline B05/B44/A05/A44 |
| 13–14 | Initial erase status and last polled status (raw observations) |
| 15–18 | Continuously enabled B05/B44/A05/A44 |
| 19–22 | After register cycle B05/B44/A05/A44 |
| 23–24 | After new opcode and F0, B05/B44 |
| 25 | Cleanup/restoration performed (not a latch assertion) |
| 26 | Marker matched |
| 27–30 | Reserved zero |
| 31 | Sum of bytes0–30 modulo256 |

Keep output tied to the supplied runtime/library hash. Even a differential
result after an experimental core change demonstrates implementation behavior;
it does not prove the original game's failure cause or cartridge semantics.
Do not merge a normative expectation or replace a release until stronger trace
evidence and the mGBA investigation justify it.

## Linux observations (2026-10-06)

The same precommit fixture ROM, SHA-256
`1c2a84921e64721dded4b9592ff822db27fcc4050f7a84facf1c763e1b87be87`,
symbols `686aad3449f7a49afedb27103bb59b5bf702dc37a81d6762ae98b76b79bc873e`,
ran normally on both supplied libraries. Each run passed21 fixture-integrity
checks; the positive ROM outcome was INFO, not a latch compatibility PASS.

| Observation B05/B44 | Installed release | Experimental candidate |
|---|---|---|
| Before erase | A5/C3 | A5/C3 |
| Erase/F0/remap, continuously enabled | FF/FF | FF/FF |
| After register disable/enable cycle | FF/FF | A5/C3 |
| After new90 opcode/F0 | A5/C3 | A5/C3 |

A-window control reads remained A5/C3 throughout; initial/ready erase status
was00/80. In both runs, sector7 was entirely erased and all other flash bytes,
hidden map and metadata were preserved. No-marker runs skipped erase and left
the whole sidecar unchanged. Safe M6TS remained15/0/0/5, checksum42.

- Installed release: embedded `0.11-feature/mbc6-complete-9341-ed393f522`,
  library SHA-256 `d764a3ea9606d05c932e01b9dc7b2741a8edee87e89727c1adb8b55ad9578516`,
  report `/tmp/mbc6-latch-njx20t7c/report.json`.
- Candidate: embedded `0.11-feature/full_server-9341-ed393f522-dirty`,
  library SHA-256 `0122452480576dd1942e932523f30a3e95ddc288fc94906184e1fe2b3fe8fbbc`,
  report `/tmp/mbc6-latch-9ekuuow8/report.json`. The embedded dirty commit
  identifies a modified working tree, not a clean committed core revision.

This differential confirms the implementation change is observable after the
enable cycle while preserving the continuously-enabled result. It does not
independently prove that this is the hardware rule or the original-game
MOVE/DELETE failure cause. The mGBA owner reports natural maintenance runs
improved with this candidate; those runs are separate from this fixture.
