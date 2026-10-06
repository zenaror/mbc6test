/* Disposable mGBA observation harness. Entry uses normal boot and joypad. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <mgba/core/core.h>
#include <mgba/core/config.h>
#include <mgba/core/directories.h>
#include <mgba/core/version.h>
#include <mgba/internal/gb/input.h>
#include <mgba-util/vfs.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static unsigned symbol(const char* path, const char* name) {
    FILE* f = fopen(path, "r");
    if (!f) return 0;
    char line[512], entry[256];
    unsigned bank, address;
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "%x:%x %255s", &bank, &address, entry) == 3 &&
            bank == 0 && !strcmp(entry, name)) {
            fclose(f);
            return address;
        }
    }
    fclose(f);
    return 0;
}

static int snapshot(const char* dir, const char* name,
                    const unsigned char* bytes, size_t length) {
    char path[PATH_MAX];
    if (snprintf(path, sizeof(path), "%s/%s", dir, name) >= (int)sizeof(path)) return 1;
    FILE* f = fopen(path, "wb");
    if (!f) return 1;
    int failed = fwrite(bytes, 1, length, f) != length;
    int closed = fclose(f);
    return failed || closed;
}

static void json_string(const char* value) {
    putchar('"');
    if (value) for (const unsigned char* p = (const unsigned char*)value; *p; ++p) {
        if (*p == '"' || *p == '\\') printf("\\%c", *p);
        else if (*p < 32) printf("\\u%04x", *p);
        else putchar(*p);
    }
    putchar('"');
}

static int disposable_path(const char* path, char* resolved, int directory) {
    static const char prefix[] = "/tmp/mbc6-latch-";
    struct stat st;
    if (!realpath(path, resolved) || strncmp(resolved, prefix, sizeof(prefix) - 1) ||
        stat(resolved, &st) || st.st_uid != getuid()) return 0;
    return directory ? S_ISDIR(st.st_mode) : S_ISREG(st.st_mode);
}

int main(int argc, char** argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: mgba_latch_runner ROM SYM EXISTING_DISPOSABLE_DIR\n");
        return 2;
    }
    char rom[PATH_MAX], dir[PATH_MAX];
    if (!disposable_path(argv[1], rom, 0) || !disposable_path(argv[3], dir, 1)) {
        fprintf(stderr, "ROM/save directory must be owned disposable /tmp/mbc6-latch-* paths\n");
        return 3;
    }
    unsigned done_address = symbol(argv[2], "wLatchDone");
    unsigned record_address = symbol(argv[2], "wLatchRecord");
    unsigned page_address = symbol(argv[2], "wCurrentPage");
    if (done_address < 0xC000 || done_address >= 0xD000 ||
        record_address < 0xC000 || record_address > 0xCFE0) {
        fprintf(stderr, "missing/invalid WRAM0 wLatchDone/wLatchRecord symbols\n");
        return 4;
    }
    struct mCore* core = mCoreFind(rom);
    if (!core || !core->init(core)) return 6;
    mCoreInitConfig(core, "mbc6-latch");
    int loaded = 0, captured = 0, result = 7;
    unsigned polling = 0, done = 0, frames = 0, page = 255, wram_bank = 0;
    if (!mCoreLoadFile(core, rom)) goto cleanup;
    loaded = 1;
    core->dirs.save = VDirOpen(dir);
    if (!core->dirs.save) goto cleanup;
    strcpy(core->dirs.baseName, "run");
    if (!mCoreAutoloadSave(core)) goto cleanup;
    core->reset(core);
    for (unsigned i = 0; i < 900; ++i) core->runFrame(core);
    unsigned combo = (1u << GB_KEY_A) | (1u << GB_KEY_B) | (1u << GB_KEY_START);
    core->setKeys(core, combo);
    for (unsigned i = 0; i < 130; ++i) core->runFrame(core);
    core->setKeys(core, 0);
    while (!core->busRead8(core, done_address) && polling < 30000) {
        core->runFrame(core);
        ++polling;
    }
    for (unsigned i = 0; i < 100; ++i) core->runFrame(core);
    done = core->busRead8(core, done_address);
    frames = core->frameCounter(core);
    if (page_address >= 0xC000 && page_address < 0xD000)
        page = core->busRead8(core, page_address);
    wram_bank = core->busRead8(core, 0xFF70) & 7;
    /* Read final SRAM records only; never redirect the CPU or issue flash commands. */
    core->busWrite8(core, 0x0000, 0x0A);
    core->busWrite8(core, 0x0800, 7);
    unsigned char suite[21], latch[32];
    for (unsigned i = 0; i < sizeof(suite); ++i) suite[i] = core->busRead8(core, 0xBF00 + i);
    for (unsigned i = 0; i < sizeof(latch); ++i) latch[i] = core->busRead8(core, 0xBF60 + i);
    result = snapshot(dir, "m6ts.bin", suite, sizeof(suite)) ||
             snapshot(dir, "m6fl.bin", latch, sizeof(latch)) ? 8 : (done ? 0 : 9);
    captured = 1;
cleanup:
    /* Unload flushes the flash sidecar before the caller reads it. */
    if (loaded) core->unloadROM(core);
    mCoreConfigDeinit(&core->config);
    core->deinit(core);
    if (captured) {
        printf("{\"projectVersion\":"); json_string(projectVersion);
        printf(",\"gitCommit\":"); json_string(gitCommit);
        printf(",\"gitBranch\":"); json_string(gitBranch);
        printf(",\"frames\":%u,\"pollingFrames\":%u,\"done\":%u,\"currentPage\":%u,"
               "\"wramBank\":%u,\"doneAddress\":%u,\"recordAddress\":%u}\n",
               frames, polling, done, page, wram_bank, done_address, record_address);
    }
    return result;
}
