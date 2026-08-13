# =====================================================================
# Project:     ESP32-C3 Bare-Metal Host & RISC-V Kernel Build Pipeline
# Description: Compiles the RISC-V kernel, creates a symlink, and 
#              builds the x86_64 host loader in the root directory.
# =====================================================================

OUT      := build

# Host Files (x86_64)
SRC_HOST := esp32c3_host.s
OBJ_HOST := $(OUT)/esp32c3_host.o
EXE_HOST := esp32c3_host

# Kernel Files (RISC-V)
SRC_KRNL := esp32c3_kernel.s
OBJ_KRNL := $(OUT)/esp32c3_kernel.o
ELF_KRNL := $(OUT)/esp32c3_kernel.elf
BIN_KRNL := $(OUT)/esp32c3_kernel.bin
SYM_KRNL := esp32c3_kernel.bin

# Host Toolchain
AS       := as
LD       := ld
ASFLAGS  := --64

# RISC-V Toolchain for ESP32-C3
RV_AS    := riscv64-unknown-elf-as
RV_LD    := riscv64-unknown-elf-ld
RV_OBJ   := riscv64-unknown-elf-objcopy
RV_FLAGS := -march=rv32imc_zicsr -mabi=ilp32

.PHONY: all run trace clean

all: $(EXE_HOST)

$(OUT):
	mkdir -p $(OUT)

# 1. Compile and link the RISC-V kernel to a flat binary blob
$(OBJ_KRNL): $(SRC_KRNL) | $(OUT)
	$(RV_AS) $(RV_FLAGS) -o $@ $<

$(ELF_KRNL): $(OBJ_KRNL)
	$(RV_LD) -m elf32lriscv -T esp32c3_linker.ld -o $@ $<

$(BIN_KRNL): $(ELF_KRNL)
	$(RV_OBJ) -O binary $< $@

# Create a symlink in the root directory pointing to the build/ binary
$(SYM_KRNL): $(BIN_KRNL)
	ln -sf $< $@

# 2. Compile and link the x86_64 host program
# (Depends on the symlink being created first so .incbin works)
$(OBJ_HOST): $(SRC_HOST) $(SYM_KRNL) | $(OUT)
	$(AS) $(ASFLAGS) -o $@ $<

$(EXE_HOST): $(OBJ_HOST)
	$(LD) -s -o $@ $<

run: all
	sudo ./$(EXE_HOST)

trace: all
	sudo strace ./$(EXE_HOST)

clean:
	rm -rf $(OUT) $(EXE_HOST) $(SYM_KRNL)
