/* Disposable Linux mGBA harness. ROM entry is exclusively normal boot/joypad. */
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
#include <stddef.h>
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
            !strcmp(entry, name) && bank == 0) {
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
    return fclose(f) || failed;
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
    static const char prefix[] = "/tmp/mbc6-offline-";
    struct stat st;
    if (!realpath(path, resolved) || strncmp(resolved, prefix, sizeof(prefix) - 1) ||
        stat(resolved, &st) || st.st_uid != getuid()) return 0;
    return directory ? S_ISDIR(st.st_mode) : S_ISREG(st.st_mode);
}

int main(int argc, char** argv) {
    int cancelled = argc == 5 && !strcmp(argv[4], "--cancel");
    if (argc != 4 && !cancelled) {
        fprintf(stderr, "usage: mgba_offline_runner ROM SYM EXISTING_DISPOSABLE_DIR [--cancel]\n");
        return 2;
    }
    char rom[PATH_MAX], dir[PATH_MAX];
    if (!disposable_path(argv[1], rom, 0) || !disposable_path(argv[3], dir, 1)) {
        fprintf(stderr, "ROM/save directory must be owned disposable /tmp/mbc6-offline-* paths\n");
        return 3;
    }
    unsigned done_address = symbol(argv[2], "wOfflineDone");
    unsigned record_address = symbol(argv[2], "wOfflineRecord");
    unsigned page_address = symbol(argv[2], "wCurrentPage");
    if (done_address < 0xC000 || done_address >= 0xD000) {
        fprintf(stderr, "missing/invalid WRAM0 wOfflineDone symbol\n");
        return 4;
    }
    if (cancelled && (record_address < 0xC000 || record_address > 0xCFE0)) {
        fprintf(stderr, "missing/invalid WRAM0 wOfflineRecord symbol\n");
        return 4;
    }
    struct mCore* core = mCoreFind(rom);
    if (!core || !core->init(core)) return 6;
    mCoreInitConfig(core, "mbc6-offline");
    int loaded = 0, result = 7;
    if (!mCoreLoadFile(core, rom)) goto cleanup;
    loaded = 1;
    core->dirs.save = VDirOpen(dir);
    if (!core->dirs.save) goto cleanup;
    strcpy(core->dirs.baseName, "run");
    if (!mCoreAutoloadSave(core)) goto cleanup;
    core->reset(core);
    /* Poison transient data before normal boot to expose stale-result bugs.
       This does not touch cartridge SRAM/flash or redirect the CPU. */
    if (cancelled) for (unsigned i = 0; i < 32; ++i)
        core->busWrite8(core, record_address + i, 0xAA);
    for (unsigned i = 0; i < 900; ++i) core->runFrame(core);
    unsigned combo = (1u << GB_KEY_A) | (1u << GB_KEY_B) | (1u << GB_KEY_START);
    core->setKeys(core, cancelled ? (1u << GB_KEY_SELECT) : combo);
    for (unsigned i = 0; i < 130; ++i) core->runFrame(core);
    core->setKeys(core, 0);
    unsigned polling = 0;
    while (!cancelled && !core->busRead8(core, done_address) && polling < 30000) {
        core->runFrame(core);
        ++polling;
    }
    for (unsigned i = 0; i < 100; ++i) core->runFrame(core);
    unsigned done = core->busRead8(core, done_address);
    unsigned page = page_address ? core->busRead8(core, page_address) : 255;
    unsigned wram_bank = core->busRead8(core, 0xFF70) & 7;
    core->busWrite8(core, 0x0000, 0x0A);
    core->busWrite8(core, 0x0800, 7);
    unsigned char suite[21], offline[32], transient[32] = {0};
    for (unsigned i = 0; i < sizeof(suite); ++i) suite[i] = core->busRead8(core, 0xBF00 + i);
    for (unsigned i = 0; i < sizeof(offline); ++i) offline[i] = core->busRead8(core, 0xBF20 + i);
    if (cancelled) for (unsigned i = 0; i < sizeof(transient); ++i)
        transient[i] = core->busRead8(core, record_address + i);
    unsigned suite_sum = 0;
    for (unsigned i = 0; i < 20; ++i) suite_sum += suite[i];
    int safe_valid = !memcmp(suite, "M6TS", 4) && suite[4] == 2 && suite[5] == 3 &&
                     suite[6] == 15 && suite[7] == 0 && suite[8] == 0 &&
                     suite[9] == 5 && (suite_sum & 255) == suite[20];
    int not_run = !memcmp(transient, "M6OF", 4) && transient[4] == 1;
    for (unsigned i = 5; i < sizeof(transient); ++i)
        if (transient[i]) not_run = 0;
    result = snapshot(dir, "m6ts.bin", suite, sizeof(suite)) ||
             snapshot(dir, "m6of.bin", offline, sizeof(offline)) ||
             (cancelled && snapshot(dir, "m6of-wram.bin", transient, sizeof(transient))) ?
             8 : (cancelled ? (!done && not_run && safe_valid ? 0 : 9) : (done ? 0 : 9));
    printf("{\"projectVersion\":"); json_string(projectVersion);
    printf(",\"gitCommit\":"); json_string(gitCommit);
    printf(",\"gitBranch\":"); json_string(gitBranch);
    printf(",\"frames\":%u,\"pollingFrames\":%u,\"done\":%u,\"cancelled\":%s,\"currentPage\":%u,\"wramBank\":%u,"
           "\"networkPolicy\":\"Headless Test ROM; no network services or adapter configured\"}\n",
           core->frameCounter(core), polling, done, cancelled ? "true" : "false", page, wram_bank);
cleanup:
    /* Closing the ROM before deinit flushes the persistent flash sidecar. */
    if (loaded) core->unloadROM(core);
    mCoreConfigDeinit(&core->config);
    core->deinit(core);
    return result;
}
