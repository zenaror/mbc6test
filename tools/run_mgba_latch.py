#!/usr/bin/env python3
"""Observe the opt-in flash-enable latch fixture in disposable /tmp state.

Requires Linux, a C compiler, the latch Test ROM/SYM and matching mGBA
source/library. Continuous/cycled latch reads are observations, not assertions
about hardware. Every invocation creates new /tmp/mbc6-latch-* fixtures.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

ARRAY_SIZE = 0x100000
FLASH_SIZE = 0x100101
SECTOR_START = 0xE0000
ERASE_BANK = 112
OTHER_BANK = 96
MARKER = b"M6LATCHFIXTUREON"
REPO = Path(__file__).resolve().parent.parent


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def symbols(path):
    result = {}
    for line in path.read_text().splitlines():
        fields = line.split()
        if len(fields) >= 2 and ":" in fields[0]:
            try:
                bank, address = fields[0].split(":", 1)
                result[fields[1]] = (int(bank, 16), int(address, 16))
            except ValueError:
                pass
    return result


def seed(marker):
    # Bank identity and both offset bytes contribute to every preserved byte.
    data = bytearray((i >> 13) ^ (i & 255) ^ ((i & 0x1FFF) >> 8) ^ 0xA7
                     for i in range(ARRAY_SIZE))
    data[SECTOR_START:ARRAY_SIZE] = bytes([0x37]) * (ARRAY_SIZE - SECTOR_START)
    data[OTHER_BANK * 0x2000 + 0x05] = 0xA5
    data[OTHER_BANK * 0x2000 + 0x44] = 0xC3
    data.extend((i * 29 + 0x63) & 255 for i in range(256))
    data.append(0)  # mGBA sector-0 protection metadata.
    if marker:
        data[0x1000F0:0x100100] = MARKER
    if len(data) != FLASH_SIZE or len(MARKER) != 16:
        raise ValueError("invalid flash fixture layout")
    return bytes(data)


def git_provenance(path):
    result = {"path": str(path)}
    for name, args in (("commit", ["rev-parse", "HEAD"]),
                       ("branch", ["branch", "--show-current"]),
                       ("status", ["status", "--porcelain"])):
        p = subprocess.run(["git", "-C", str(path), *args], text=True,
                           capture_output=True, timeout=10)
        result[name] = p.stdout.strip() if p.returncode == 0 else None
    return result


def runtime_environment(library):
    env = os.environ.copy()
    env.pop("LD_PRELOAD", None)
    env.pop("LD_AUDIT", None)
    env["LD_LIBRARY_PATH"] = str(library.parent)
    return env


def compile_runner(source, library, output, report):
    includes = source / "include"
    if not (includes / "mgba/core/core.h").is_file():
        raise ValueError("--mgba-source must contain include/mgba/core/core.h")
    defines = ["-DENABLE_VFS", "-DENABLE_DIRECTORIES", "-DENABLE_INPUT"]
    # Match the supplied build's struct mCore ABI, including debugger fields.
    flags = library.parent / "CMakeFiles/mgba.dir/flags.make"
    if flags.is_file():
        for line in flags.read_text().splitlines():
            if line.startswith("C_DEFINES ="):
                defines = shlex.split(line.split("=", 1)[1])
                report["compile_flags_source"] = str(flags)
                report["compile_flags_sha256"] = sha256(flags.read_bytes())
                break
    command = [os.environ.get("CC", "cc"), "-std=c11", "-O2", "-Wall", "-Wextra",
               *defines, "-I", str(includes), str(REPO / "tools/mgba_latch_runner.c"),
               str(library), "-Wl,-rpath," + str(library.parent), "-o", str(output)]
    report["compile_command"] = command
    p = subprocess.run(command, text=True, capture_output=True, timeout=120)
    (output.parent / "compile.log").write_text(p.stdout + p.stderr)
    if p.returncode:
        raise RuntimeError("runner compilation failed; see compile.log: " + p.stderr[-2000:])
    p = subprocess.run(["ldd", str(output)], text=True, capture_output=True,
                       env=runtime_environment(library), timeout=10)
    report["ldd"] = p.stdout
    (output.parent / "ldd.txt").write_text(p.stdout + p.stderr)
    resolved = [line.split("=>", 1)[1].strip().split()[0]
                for line in p.stdout.splitlines() if "libmgba" in line and "=>" in line]
    if p.returncode or len(resolved) != 1 or not Path(resolved[0]).samefile(library):
        raise RuntimeError("runner did not resolve the exact supplied mGBA library")
    report["runner_sha256"] = sha256(output.read_bytes())


def check(report, condition, description):
    report["checks"].append({"passed": bool(condition), "description": description})
    if not condition:
        report["errors"].append(description)


def classified(raw, fixture_seed):
    matches = []
    if raw == fixture_seed:
        matches.append("fixture_seed")
    if raw == 0xFF:
        matches.append("erased_array")
    return {"raw": raw, "fixture_seed": fixture_seed, "erased_array": 255,
            "matches": matches or ["neither_seed_nor_erased"]}


def summary(data):
    if len(data) != 32:
        raise ValueError("M6FL must be 32 bytes")
    result = {"hex": data.hex(), "format": data[4], "outcome": data[5],
              "phase": data[6], "erase_bank": data[7], "other_bank": data[8],
              "baseline_collected": bool(data[26] and data[6] >= 2),
              "baseline": {"B_05": data[9], "B_44": data[10],
                           "A_05": data[11], "A_44": data[12]},
              "erase_busy_raw": data[13], "ready_raw": data[14],
              "restored": data[25], "marker": data[26], "checksum": data[31]}
    for name, start, windows, phase in (("continuous", 15, ("B", "A"), 4),
                                        ("cycled", 19, ("B", "A"), 5),
                                        ("after_new_opcode", 23, ("B",), 6)):
        result[name] = {}
        for index, window in enumerate(windows):
            for offset_index, offset in enumerate(("05", "44")):
                reference = (0xA5, 0xC3)[offset_index]
                reading = classified(data[start + 2 * index + offset_index], reference)
                reading["mapped_bank"] = OTHER_BANK
                reading["collected"] = bool(data[26] and data[6] >= phase)
                if not reading["collected"]:
                    reading["matches"] = ["not_collected"]
                result[name][window + "_" + offset] = reading
    return result


def execute(name, directory, executable, rom, sym, library, report, artifacts):
    case = {"name": name, "save_directory": str(directory)}
    report["cases"].append(case)
    p = subprocess.run([str(executable), str(rom), str(sym), str(directory)],
                       text=True, capture_output=True, env=runtime_environment(library),
                       timeout=180, close_fds=True)
    case["runner_exit"] = p.returncode
    (artifacts / (name + ".log")).write_text(p.stdout + p.stderr)
    try:
        case["core"] = json.loads(p.stdout.splitlines()[-1])
    except (ValueError, IndexError):
        case["core"] = None
    check(report, p.returncode == 0 and case["core"] and case["core"].get("done") != 0,
          name + ": normal boot/joypad completed within bounded polling")
    check(report, case["core"] and case["core"].get("wramBank") == 1,
          name + ": WRAM bank restored to 1 after settling")
    suite = (directory / "m6ts.bin").read_bytes()
    latch = (directory / "m6fl.bin").read_bytes()
    (artifacts / (name + "-m6ts.bin")).write_bytes(suite)
    (artifacts / (name + "-m6fl.bin")).write_bytes(latch)
    case["m6ts_hex"] = suite.hex()
    case["m6fl"] = summary(latch)
    check(report, len(suite) == 21 and suite[:6] == b"M6TS\x02\x03" and
          (sum(suite[:20]) & 255) == suite[20] and suite[6:10] == bytes([15, 0, 0, 5]),
          name + ": safe M6TS format2 suite3 counts 15/0/0/5 and checksum")
    check(report, latch[:5] == b"M6FL\x01" and (sum(latch[:31]) & 255) == latch[31]
          and latch[27:31] == bytes(4), name + ": M6FL ABI/checksum/reserved bytes")
    check(report, latch[7:9] == bytes([ERASE_BANK, OTHER_BANK]),
          name + ": target/other fixture bank identifiers")
    flash = (directory / "run.sav.flash").read_bytes()
    case["flash_sha256"] = sha256(flash)
    case["flash_size"] = len(flash)
    (artifacts / (name + ".flash")).write_bytes(flash)
    check(report, len(flash) == FLASH_SIZE, name + ": full sidecar size")
    sram = (directory / "run.sav").read_bytes()
    case["sram_sha256"] = sha256(sram)
    case["sram_size"] = len(sram)
    (artifacts / (name + ".sav")).write_bytes(sram)
    check(report, len(sram) == 0x8000, name + ": saved SRAM size")
    return latch, flash


def run(args, root, report):
    source, library = args.mgba_source.resolve(), args.mgba_library.resolve()
    rom_bytes, sym_bytes = args.rom.read_bytes(), args.sym.read_bytes()
    if (len(rom_bytes) != ARRAY_SIZE or rom_bytes[0x143] != 0xC0 or
            rom_bytes[0x147:0x14A] != bytes([0x20, 0x05, 0x03])):
        raise ValueError("expected 1 MiB CGB-only MBC6 Test ROM with 32 KiB SRAM")
    exported = symbols(args.sym)
    for name, maximum in (("wLatchDone", 0xCFFF), ("wLatchRecord", 0xCFE0)):
        value = exported.get(name)
        if not value or value[0] or not 0xC000 <= value[1] <= maximum:
            raise ValueError(name + " must be exported in WRAM0; use the latch fixture build")
    report["inputs"] = {"rom": str(args.rom.resolve()), "rom_sha256": sha256(rom_bytes),
                        "sym": str(args.sym.resolve()), "sym_sha256": sha256(sym_bytes),
                        "mgba_library": str(library), "mgba_library_sha256": sha256(library.read_bytes())}
    report["symbols"] = {name: list(exported[name]) for name in ("wLatchDone", "wLatchRecord")}
    report["repository"] = git_provenance(REPO)
    report["mgba_source"] = git_provenance(source)
    report["runner_source_sha256"] = sha256((REPO / "tools/mgba_latch_runner.c").read_bytes())
    report["python_source_sha256"] = sha256(Path(__file__).read_bytes())
    rom, sym = root / "fixture.gbc", root / "fixture.sym"
    rom.write_bytes(rom_bytes)
    sym.write_bytes(sym_bytes)
    executable = root / "mgba_latch_runner"
    compile_runner(source, library, executable, report)
    report["fixture_layout"] = {
        "sidecar_size": FLASH_SIZE, "erase_sector_start": SECTOR_START,
        "erase_sector_size": ARRAY_SIZE - SECTOR_START, "erase_bank": ERASE_BANK,
        "other_bank": OTHER_BANK, "sector7_seed": 0x37,
        "array_seed": "bank8KiB XOR offset_low XOR offset_high XOR A7",
        "other_bank_sentinels": {"05": 0xA5, "44": 0xC3},
        "hidden_offset": ARRAY_SIZE, "marker_offset": 0x1000F0,
        "marker_ascii": MARKER.decode("ascii"), "marker_length": len(MARKER),
        "hidden_seed": "(offset * 29 + 63hex) modulo 256",
        "protection_metadata_offset": 0x100100, "protection_metadata": 0,
    }
    positive = root / "positive"
    positive.mkdir(mode=0o700)
    initial = seed(True)
    report["initial_flash_sha256"] = sha256(initial)
    (root / "initial.flash").write_bytes(initial)
    (positive / "run.sav.flash").write_bytes(initial)
    expected = initial[:SECTOR_START] + bytes([255]) * (ARRAY_SIZE - SECTOR_START) + initial[ARRAY_SIZE:]
    report["expected_erased_flash_sha256"] = sha256(expected)
    observed, flashed = execute("observe", positive, executable, rom, sym, library, report, root)
    check(report, observed[5:7] == bytes([3, 7]), "observe: INFO/done, never a latch-value PASS expectation")
    check(report, observed[9:13] == bytes([0xA5, 0xC3, 0xA5, 0xC3]),
          "observe: bank96 baseline in both windows matches seeded sentinels before erase")
    check(report, observed[25:27] == bytes([1, 1]), "observe: mapping restored and marker accepted")
    check(report, flashed == expected,
          "observe: entire sector7 erased; all other array bytes/hidden map/metadata preserved")
    negative = root / "no-marker"
    negative.mkdir(mode=0o700)
    no_marker = seed(False)
    report["no_marker_initial_flash_sha256"] = sha256(no_marker)
    (root / "no-marker-initial.flash").write_bytes(no_marker)
    (negative / "run.sav.flash").write_bytes(no_marker)
    skipped_record, skipped = execute("no-marker", negative, executable, rom, sym, library, report, root)
    check(report, skipped_record[5:7] == bytes([2, 1]) and skipped_record[25:27] == bytes([1, 0]),
          "no-marker: SKIP at marker gate before erase, cleanup performed")
    check(report, skipped == no_marker, "no-marker: entire sidecar unchanged")
    check(report, sha256(library.read_bytes()) == report["inputs"]["mgba_library_sha256"],
          "mGBA library hash unchanged throughout the runs")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rom", type=Path, required=True)
    parser.add_argument("--sym", type=Path, required=True)
    parser.add_argument("--mgba-source", type=Path, required=True)
    parser.add_argument("--mgba-library", type=Path, required=True)
    args = parser.parse_args()
    if sys.platform != "linux":
        parser.error("this disposable runtime harness currently supports Linux")
    root = Path(tempfile.mkdtemp(prefix="mbc6-latch-", dir="/tmp"))
    report = {"format": 1, "output_directory": str(root), "checks": [], "errors": [],
              "cases": [], "hardware_validated": False,
              "entry": "normal boot; 900 frames; A+B+Start 130 frames; bounded wLatchDone polling; 100 final frames",
              "interpretation": "continuous/cycled/new-opcode reads are raw observations; checks validate fixture setup and persistence only"}
    print("Output: " + str(root), flush=True)
    try:
        run(args, root, report)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report["errors"].append(str(error))
    report["passed"] = not report["errors"]
    report_path = root / "report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    for name in ("rom", "sym", "mgba_library"):
        digest = report.get("inputs", {}).get(name + "_sha256")
        if digest:
            print(name + "_sha256=" + digest)
    for case in report["cases"]:
        block, core = case.get("m6fl", {}), case.get("core") or {}
        print(f"{case['name']}: outcome={block.get('outcome')} phase={block.get('phase')} "
              f"mGBA={core.get('projectVersion')} git={core.get('gitCommit')} "
              f"branch={core.get('gitBranch')} flash_sha256={case.get('flash_sha256')}")
        if block.get("outcome") == 3:
            for phase in ("continuous", "cycled", "after_new_opcode"):
                reads = block.get(phase, {})
                print(phase + ": " + " ".join(f"{name}={value['raw']:02X}" for name, value in reads.items()))
    for error in report["errors"]:
        print("FAIL: " + error, file=sys.stderr)
    print(("PASS" if report["passed"] else "FAIL") + ": " + str(report_path))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
