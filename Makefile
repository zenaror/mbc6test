# MBC6 test ROM build.
#
# See docs/project-rules.md "Mandatory build workflow": after source/layout changes
# run `make` then `make verify`. `make test` is build + static
# verification only — it does not prove runtime mapper correctness.

RGBASM  ?= rgbasm
RGBLINK ?= rgblink
RGBFIX  ?= rgbfix
PYTHON3 ?= python3

BUILD_DIR := build
SRC_DIR   := src
INC_DIR   := include
TOOLS_DIR := tools

# .gbc, not .gb: this ROM is CGB-only ($0143=$C0), and at least one
# widely-used emulator (mGBA) was observed treating the file extension
# as an additional signal for CGB-vs-DMG mode selection, independent
# of the header byte — see docs/mbc6-notes.md.
ROM        := $(BUILD_DIR)/mbc6-test.gbc
MAP        := $(BUILD_DIR)/mbc6-test.map
SYM        := $(BUILD_DIR)/mbc6-test.sym

# Destructive flash tests are compile-time disabled by default.
# docs/project-rules.md "Destructive flash policy": default must be OFF.
ENABLE_DESTRUCTIVE_FLASH_TESTS ?= 0

GENERATED := $(SRC_DIR)/bank_data.asm $(SRC_DIR)/bank_data_fixed.asm $(SRC_DIR)/font_data.asm $(SRC_DIR)/build_info.asm

# Force the generators to run at parse time (not just as a recipe
# prerequisite) so $(wildcard) below always sees the generated files —
# otherwise, right after `make clean`, SOURCES would be computed
# before the generated .asm files exist and the build would need two
# passes.
$(if $(wildcard $(SRC_DIR)/bank_data.asm $(SRC_DIR)/bank_data_fixed.asm),,$(shell $(PYTHON3) $(TOOLS_DIR)/gen_bank_data.py >&2))
$(if $(wildcard $(SRC_DIR)/font_data.asm),,$(shell $(PYTHON3) $(TOOLS_DIR)/gen_font.py >&2))
# build_info.asm is NOT guarded like the others above — it must be
# regenerated on every invocation (unconditionally), since the git
# commit/dirty state can change without any tracked source file
# changing, and the whole point is that it always reflects the
# current HEAD.
$(shell $(PYTHON3) $(TOOLS_DIR)/gen_build_info.py >&2)

SOURCES := $(wildcard $(SRC_DIR)/*.asm)
OBJECTS := $(patsubst $(SRC_DIR)/%.asm,$(BUILD_DIR)/%.o,$(SOURCES))

RGBASM_FLAGS := -I $(INC_DIR) -I $(SRC_DIR) \
                -D ENABLE_DESTRUCTIVE_FLASH_TESTS=$(ENABLE_DESTRUCTIVE_FLASH_TESTS)

# Re-running `make` with a different ENABLE_DESTRUCTIVE_FLASH_TESTS
# value than the previous build used must not silently reuse stale
# .o files compiled with the old value. This stamp file's name
# encodes the flag value; when it changes, the old stamp is removed
# and the new (freshly-touched) one is newer than every existing .o,
# forcing a full rebuild without requiring `make clean` first.
FLAG_STAMP := $(BUILD_DIR)/.flags-$(ENABLE_DESTRUCTIVE_FLASH_TESTS)

.PHONY: all clean verify test generate .FORCE

all: $(ROM)

generate:
	$(PYTHON3) $(TOOLS_DIR)/gen_bank_data.py
	$(PYTHON3) $(TOOLS_DIR)/gen_font.py
	$(PYTHON3) $(TOOLS_DIR)/gen_build_info.py

$(SRC_DIR)/bank_data.asm $(SRC_DIR)/bank_data_fixed.asm: $(TOOLS_DIR)/gen_bank_data.py $(TOOLS_DIR)/mbc6_layout.py
	$(PYTHON3) $(TOOLS_DIR)/gen_bank_data.py

$(SRC_DIR)/font_data.asm: $(TOOLS_DIR)/gen_font.py
	$(PYTHON3) $(TOOLS_DIR)/gen_font.py

# .FORCE (not a real file) makes this target's recipe run every time,
# matching the always-regenerate behavior above.
$(SRC_DIR)/build_info.asm: .FORCE
	$(PYTHON3) $(TOOLS_DIR)/gen_build_info.py

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(FLAG_STAMP): | $(BUILD_DIR)
	rm -f $(BUILD_DIR)/.flags-*
	touch $(FLAG_STAMP)

# Every source file may depend on the shared includes and generated
# bank data; keeping the dependency coarse-grained is safe and cheap
# for a project this size.
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.asm $(wildcard $(INC_DIR)/*.inc) $(GENERATED) $(FLAG_STAMP) | $(BUILD_DIR)
	$(RGBASM) $(RGBASM_FLAGS) -o $@ $<

$(ROM): $(OBJECTS) | $(BUILD_DIR)
	$(RGBLINK) -m $(MAP) -n $(SYM) -o $@ $(OBJECTS)
	$(RGBFIX) -v -p 0xFF \
		-C \
		-m MBC6 \
		-r 0x03 \
		-l 0x33 \
		-n 0x00 \
		-j \
		-t "MBC6 TEST" \
		$@

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(GENERATED)

verify: $(ROM)
	$(PYTHON3) $(TOOLS_DIR)/verify_rom.py $(ROM)

test: verify
