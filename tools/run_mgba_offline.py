#!/usr/bin/env python3
"""Run the opt-in offline fixture in new disposable /tmp/mbc6-offline-* state.

Uses only the homebrew Test ROM; no server, download or network adapter is
configured. Requires Linux, a C compiler and matching mGBA source/library.
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

FLASH_SIZE = 0x100101
ARRAY_SIZE = 0x100000
SECTOR_START = 0xE0000
PAYLOAD_SIZE = 0x2000
MARKER = b"M6OFFLINEFIXTURE"
REPO = Path(__file__).resolve().parent.parent


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def symbols(path):
    result = {}
    for line in path.read_text().splitlines():
        fields = line.split()
        if len(fields) >= 2 and ":" in fields[0]:
            bank, address = fields[0].split(":", 1)
            try:
                result[fields[1]] = (int(bank, 16), int(address, 16))
            except ValueError:
                pass
    return result


def payload(rom, sym):
    start = sym.get("OfflinePayloadTemplate")
    end = sym.get("OfflinePayloadTemplateEnd")
    if not start or not end or start[0] or end[0] or not 0 <= start[1] < end[1] <= 0x4000:
        raise ValueError("OfflinePayloadTemplate/End must be exported in ROM0")
    template = rom[start[1]:end[1]]
    if not template or len(template) > PAYLOAD_SIZE:
        raise ValueError("invalid offline payload template size")
    data = bytearray((i & 255) ^ (i >> 8) ^ 0x5A for i in range(PAYLOAD_SIZE))
    data[:len(template)] = template
    return bytes(data)


def seed(marker):
    # Every byte of all seven preserved sectors is a deterministic sentinel.
    data = bytearray((i & 255) ^ ((i >> 8) & 255) ^ (i >> 16) ^ 0xA7
                     for i in range(ARRAY_SIZE))
    # Garbage throughout sector 7 makes the full erase externally observable.
    data[SECTOR_START:ARRAY_SIZE] = bytes([0x37]) * (ARRAY_SIZE - SECTOR_START)
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
               *defines, "-I", str(includes), str(REPO / "tools/mgba_offline_runner.c"),
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


def check(report, condition, description):
    report["checks"].append({"passed": bool(condition), "description": description})
    if not condition:
        report["errors"].append(description)


def summary(data):
    if len(data) != 32:
        raise ValueError("M6OF must be 32 bytes")
    return {"hex": data.hex(), "format": data[4], "status": data[5], "phase": data[6],
            "mode": data[7], "pages": data[8], "initial_busy_raw": data[9],
            "ready_raw": data[10], "receipt": list(data[11:13]),
            "sum16": int.from_bytes(data[13:15], "little"),
            "expected_sum16": int.from_bytes(data[15:17], "little"),
            "failure_offset": int.from_bytes(data[17:19], "little"),
            "failure_expected": data[19], "failure_actual": data[20],
            "restored": data[21], "marker": data[22], "checksum": data[31]}


def execute(name, directory, executable, rom, sym, library, report, artifacts, confirmed=True):
    case = {"name": name, "save_directory": str(directory), "confirmed": confirmed}
    report["cases"].append(case)
    command = [str(executable), str(rom), str(sym), str(directory)]
    if not confirmed:
        command.append("--cancel")
    p = subprocess.run(command,
                       text=True, capture_output=True, env=runtime_environment(library),
                       timeout=180, close_fds=True)
    case["runner_exit"] = p.returncode
    (artifacts / (name + ".log")).write_text(p.stdout + p.stderr)
    try:
        case["core"] = json.loads(p.stdout.splitlines()[-1])
    except (ValueError, IndexError):
        case["core"] = None
    check(report, p.returncode == 0 and case["core"] and
          ((case["core"]["done"] != 0) if confirmed else (case["core"]["done"] == 0)),
          name + (": normal boot/joypad completed within bounded polling" if confirmed
                  else ": SELECT cancellation returned to UI with done=0"))
    check(report, case["core"] and case["core"].get("wramBank") == 1,
          name + ": WRAM bank restored to 1 after final settling frames")
    suite = (directory / "m6ts.bin").read_bytes()
    offline = (directory / "m6of.bin").read_bytes()
    (artifacts / (name + "-m6ts.bin")).write_bytes(suite)
    (artifacts / (name + "-m6of.bin")).write_bytes(offline)
    case["m6ts_hex"] = suite.hex()
    case["m6of"] = summary(offline)
    if not confirmed:
        transient = (directory / "m6of-wram.bin").read_bytes()
        (artifacts / (name + "-m6of-wram.bin")).write_bytes(transient)
        case["m6of_wram"] = summary(transient)
        check(report, transient[:5] == b"M6OF\x01" and transient[5:] == bytes(27),
              name + ": poisoned transient record initialized to NOTRUN with zero status/mode/pages/receipts")
    check(report, len(suite) == 21 and suite[:6] == b"M6TS\x02\x03" and
          (sum(suite[:20]) & 255) == suite[20] and suite[6:10] == bytes([15, 0, 0, 5]),
          name + ": safe M6TS format2 suite3 counts 15/0/0/5 and checksum")
    check(report, offline[:5] == b"M6OF\x01" and (sum(offline[:31]) & 255) == offline[31]
          and offline[23:31] == bytes(8), name + ": M6OF ABI/checksum/reserved bytes")
    flash = (directory / "run.sav.flash").read_bytes()
    case["flash_sha256"] = sha256(flash)
    case["flash_size"] = len(flash)
    (artifacts / (name + ".flash")).write_bytes(flash)
    check(report, len(flash) == FLASH_SIZE, name + ": full sidecar size")
    saved_sram = (directory / "run.sav").read_bytes()
    case["sram_sha256"] = sha256(saved_sram)
    case["sram_size"] = len(saved_sram)
    (artifacts / (name + ".sav")).write_bytes(saved_sram)
    check(report, len(saved_sram) == 0x8000, name + ": saved SRAM size")
    return offline, flash


def run(args, root, report):
    source, library = args.mgba_source.resolve(), args.mgba_library.resolve()
    rom_bytes, sym_bytes = args.rom.read_bytes(), args.sym.read_bytes()
    if len(rom_bytes) != ARRAY_SIZE or rom_bytes[0x143] != 0xC0 or rom_bytes[0x147] != 0x20:
        raise ValueError("expected 1 MiB CGB-only MBC6 Test ROM")
    expected = payload(rom_bytes, symbols(args.sym))
    report["inputs"] = {"rom": str(args.rom.resolve()), "rom_sha256": sha256(rom_bytes),
                        "sym": str(args.sym.resolve()), "sym_sha256": sha256(sym_bytes),
                        "mgba_library": str(library), "mgba_library_sha256": sha256(library.read_bytes()),
                        "payload_sha256": sha256(expected), "payload_sum16": sum(expected) & 65535}
    report["repository"] = git_provenance(REPO)
    report["mgba_source"] = git_provenance(source)
    report["runner_source_sha256"] = sha256((REPO / "tools/mgba_offline_runner.c").read_bytes())
    report["python_source_sha256"] = sha256(Path(__file__).read_bytes())
    rom, sym = root / "fixture.gbc", root / "fixture.sym"
    rom.write_bytes(rom_bytes)
    sym.write_bytes(sym_bytes)
    executable = root / "mgba_offline_runner"
    compile_runner(source, library, executable, report)
    positive = root / "positive"
    positive.mkdir(mode=0o700)
    initial = seed(True)
    report["initial_flash_sha256"] = sha256(initial)
    report["fixture_layout"] = {
        "sidecar_size": FLASH_SIZE, "payload_offset": SECTOR_START,
        "payload_size": PAYLOAD_SIZE, "hidden_offset": ARRAY_SIZE,
        "marker_offset": 0x1000F0, "marker_ascii": MARKER.decode("ascii"),
        "protection_metadata_offset": 0x100100,
    }
    (root / "initial.flash").write_bytes(initial)
    (positive / "run.sav.flash").write_bytes(initial)
    expected_flash = (initial[:SECTOR_START] + expected +
                      bytes([255]) * (ARRAY_SIZE - SECTOR_START - PAYLOAD_SIZE) + initial[ARRAY_SIZE:])
    report["expected_installed_flash_sha256"] = sha256(expected_flash)
    installed_summary, installed = execute("install", positive, executable, rom, sym, library, report, root)
    check(report, installed_summary[5:9] == bytes([1, 7, 1, 64]), "install: PASS/done/install/64 pages")
    check(report, installed == expected_flash, "install: full payload, erased sector tail, other sectors/hidden map/metadata preserved")
    check(report, installed_summary[11:13] == bytes([0xA6, 0x5A]) and installed_summary[21:23] == bytes([1, 1]),
          "install: payload executed/returned, mapping restored and marker accepted")
    check(report, int.from_bytes(installed_summary[13:15], "little") == (sum(expected) & 65535) and
          installed_summary[13:15] == installed_summary[15:17], "install: complete 8192-byte checksum")
    reopened_summary, reopened = execute("reopen", positive, executable, rom, sym, library, report, root)
    check(report, reopened_summary[5:9] == bytes([1, 7, 2, 0]), "reopen: PASS/done/reopen/zero programmed pages")
    check(report, reopened_summary[11:13] == bytes([0xA6, 0x5A]) and reopened_summary[21:23] == bytes([1, 1]),
          "reopen: persisted payload executed/returned and mapping restored")
    check(report, reopened_summary[13:15] == reopened_summary[15:17] and
          int.from_bytes(reopened_summary[13:15], "little") == (sum(expected) & 65535),
          "reopen: complete 8192-byte checksum")
    check(report, reopened == installed == expected_flash, "reopen: entire sidecar unchanged across fresh core")
    cancelled = root / "cancel"
    cancelled.mkdir(mode=0o700)
    (cancelled / "run.sav").write_bytes((root / "reopen.sav").read_bytes())
    (cancelled / "run.sav.flash").write_bytes(installed)
    cancelled_summary, cancelled_flash = execute("cancel", cancelled, executable, rom,
                                                 sym, library, report, root, confirmed=False)
    check(report, cancelled_summary == reopened_summary,
          "cancel: previously completed persisted M6OF record preserved bytewise")
    check(report, cancelled_flash == installed, "cancel: entire installed sidecar unchanged")
    # A valid checksum must not make an incomplete prior record acceptable.
    # Reuse a snapshot of the positive reopen SRAM, leaving its flash intact.
    invalid_record = root / "invalid-prior-record"
    invalid_record.mkdir(mode=0o700)
    invalid_sram = bytearray((root / "reopen.sav").read_bytes())
    invalid_sram[0x7F20 + 6] = 6  # phase EXEC, not successful completion.
    invalid_sram[0x7F20 + 31] = sum(invalid_sram[0x7F20:0x7F20 + 31]) & 255
    (invalid_record / "run.sav").write_bytes(invalid_sram)
    (invalid_record / "run.sav.flash").write_bytes(installed)
    (root / "invalid-prior-record-initial.sav").write_bytes(invalid_sram)
    report["invalid_prior_record_initial_sram_sha256"] = sha256(invalid_sram)
    invalid_summary, invalid_flash = execute("invalid-prior-record", invalid_record,
                                             executable, rom, sym, library, report, root)
    check(report, invalid_summary[5:9] == bytes([2, 2, 2, 0]) and
          invalid_summary[11:13] == bytes(2),
          "invalid-prior-record: FAIL during resume before programming/execution despite valid checksum")
    check(report, invalid_flash == installed,
          "invalid-prior-record: entire installed sidecar unchanged")
    negative = root / "no-marker"
    negative.mkdir(mode=0o700)
    no_marker = seed(False)
    report["no_marker_initial_flash_sha256"] = sha256(no_marker)
    (negative / "run.sav.flash").write_bytes(no_marker)
    skipped_summary, skipped = execute("no-marker", negative, executable, rom, sym, library, report, root)
    check(report, skipped_summary[5:9] == bytes([3, 1, 0, 0]) and skipped_summary[11:13] == bytes(2)
          and skipped_summary[21:23] == bytes(2), "no-marker: SKIP before erase/program/execute")
    check(report, skipped == no_marker, "no-marker: entire sidecar unchanged")
    corrupt = bytearray(installed)
    corrupt[SECTOR_START + 0x100] ^= 1
    report["corrupt_initial_flash_sha256"] = sha256(corrupt)
    (positive / "run.sav.flash").write_bytes(corrupt)
    (root / "corrupt-initial.flash").write_bytes(corrupt)
    corrupt_summary, corrupted = execute("corrupt", positive, executable, rom, sym, library, report, root)
    check(report, corrupt_summary[5:9] == bytes([2, 5, 2, 0]) and corrupt_summary[11:13] == bytes(2),
          "corrupt: FAIL during reopen/verify with zero writes/no payload execution")
    check(report, int.from_bytes(corrupt_summary[17:19], "little") == 0x100 and
          corrupt_summary[19] == expected[0x100] and corrupt_summary[20] == corrupt[SECTOR_START + 0x100],
          "corrupt: first-failure offset/expected/actual match injected byte")
    check(report, corrupt_summary[21:23] == bytes([0, 1]), "corrupt: no success restoration receipt and marker accepted")
    check(report, corrupted == bytes(corrupt), "corrupt: entire sidecar unchanged; no rewrite")
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
    root = Path(tempfile.mkdtemp(prefix="mbc6-offline-", dir="/tmp"))
    report = {"format": 1, "output_directory": str(root), "checks": [], "errors": [], "cases": [],
              "hardware_validated": False,
              "entry": "normal boot; 900 frames; A+B+Start or SELECT for 130 frames; bounded polling on confirmation; 100 final frames",
              "network": "headless Test ROM; no server, download or network adapter configuration"}
    print("Output: " + str(root), flush=True)
    try:
        run(args, root, report)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report["errors"].append(str(error))
    report["passed"] = not report["errors"]
    report_path = root / "report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    for name in ("rom", "sym", "mgba_library", "payload"):
        digest = report.get("inputs", {}).get(name + "_sha256")
        if digest:
            print(name + "_sha256=" + digest)
    for case in report["cases"]:
        block = case.get("m6of_wram", case.get("m6of", {}))
        core = case.get("core") or {}
        record_kind = "WRAM" if "m6of_wram" in case else "SRAM"
        print(f"{case['name']}: record={record_kind} status={block.get('status')} mode={block.get('mode')} "
              f"pages={block.get('pages')} mGBA={core.get('projectVersion')} "
              f"git={core.get('gitCommit')} branch={core.get('gitBranch')} "
              f"flash_sha256={case.get('flash_sha256')}")
    for error in report["errors"]:
        print("FAIL: " + error, file=sys.stderr)
    print(("PASS" if report["passed"] else "FAIL") + ": " + str(report_path))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
