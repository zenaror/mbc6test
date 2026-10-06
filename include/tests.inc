; Test result model and test IDs.
; See docs/project-rules.md "Test statuses" / "Required safe tests" and
; docs/test-matrix.md for the authoritative description of each test.

DEF RESULT_PASS EQU 0
DEF RESULT_FAIL EQU 1
DEF RESULT_SKIP EQU 2
DEF RESULT_INFO EQU 3
; Not one of docs/project-rules.md's four semantic result classes — internal-only
; sentinel so the on-screen results grid can tell "never ran this
; build" (e.g. TD1-TD12 in a safe build) apart from an actual PASS,
; which is numerically 0. ResetTestState initializes every slot to
; this; RecordResult overwrites it for whichever tests actually run.
DEF RESULT_NOT_RUN EQU 4

; ---- Test IDs (index into wTestStatus; keep contiguous from 0) ----
DEF T_00 EQU 0  ; startup / header sanity
DEF T_01 EQU 1  ; power-on mapper state capture
DEF T_10 EQU 2  ; ROM Bank A full sweep
DEF T_11 EQU 3  ; ROM Bank B full sweep
DEF T_12 EQU 4  ; ROM Bank A/B independence
DEF T_13 EQU 5  ; ROM bank 0 mapping
DEF T_14 EQU 6  ; ROM window boundaries
DEF T_20 EQU 7  ; SRAM disabled behavior
DEF T_21 EQU 8  ; SRAM Bank A sweep 0-7
DEF T_22 EQU 9  ; SRAM Bank B sweep 0-7
DEF T_23 EQU 10 ; SRAM A/B independence
DEF T_24 EQU 11 ; SRAM 4 KiB granularity
DEF T_30 EQU 12 ; ROM/Flash source-latch isolation and bank retention
DEF T_31 EQU 13 ; Flash JEDEC ID through Bank A
DEF T_32 EQU 14 ; Flash JEDEC ID through Bank B
DEF T_33 EQU 15 ; Flash reset command
DEF T_34 EQU 16 ; Hidden 256-byte region read mode (INFO)
DEF T_35 EQU 17 ; Sector-0 WP status observation (INFO; no buffer trigger)
DEF T_EX01 EQU 18 ; EXPERIMENTAL: high bank-number bit observation (INFO only)
DEF T_EX02 EQU 19 ; EXPERIMENTAL: $C6 bank-type write observation (INFO only)

; ---- Destructive test IDs (ENABLE_DESTRUCTIVE_FLASH_TESTS=1 only) ----
DEF T_TD1 EQU 20 ; Sector erase (sector 7)
DEF T_TD2 EQU 21 ; 128-byte buffered programming
DEF T_TD3 EQU 22 ; 1->0 programming semantics
DEF T_TD4 EQU 23 ; Flash ready bit and bounded software polling timeout
DEF T_TD5 EQU 24 ; Sector-0 WP behavior (INFO)
DEF T_TD6 EQU 25 ; Hidden-map erase/program (fixture-only; marker gated)
DEF T_TD7 EQU 26 ; Partial/out-of-order buffer; trigger address selects destination
DEF T_TD8 EQU 27 ; $F0 payload versus repeated-slot abort
DEF T_TD9 EQU 28 ; Hidden-map A/B observation after completed erase + $F0
DEF T_TD10 EQU 29 ; JEDEC ID cross-window observation (fixture INFO)
DEF T_TD11 EQU 30 ; Program/chip-erase status across A/B (fixture INFO)
DEF T_TD12 EQU 31 ; Buffer slots 0/127 and page edges (fixture INFO)

; NUM_TESTS must cover the destructive IDs too so wTestStatus/the
; result-block bitset (docs/result-format.md) have room for them even
; in a safe-only build — they stay at RESULT_NOT_RUN when destructive
; tests never run, and the results grid shows that distinctly from PASS.
DEF NUM_TESTS EQU 32
