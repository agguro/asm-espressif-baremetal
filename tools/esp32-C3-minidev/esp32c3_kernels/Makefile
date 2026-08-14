# =====================================================================
# Project:     ESP32-C3 Bare-Metal Kernel Build System
# Makefile:    Makefile.kernel (Kernel Only)
# =====================================================================

RV_AS   = riscv64-unknown-elf-as
RV_LD   = riscv64-unknown-elf-ld
RV_OBJ  = riscv64-unknown-elf-objcopy
RV_DUMP = riscv64-unknown-elf-objdump

RV_ASFLAGS = -march=rv32imc_zicsr -mabi=ilp32
RV_LDFLAGS = -m elf32lriscv -T esp32c3_kernel_linker.ld

.PHONY: all release debug clean

all: release

# ---------------------------------------------------------------------
# RELEASE TARGET (Only binary output)
# ---------------------------------------------------------------------
release: build/release/esp32c3_kernel.bin
	@echo "[BUILD] Release kernel build completed in build/release/"

build/release/esp32c3_kernel.bin: esp32c3_kernel.s esp32c3_kernel_linker.ld
	mkdir -p build/release
	$(RV_AS) $(RV_ASFLAGS) -o build/release/esp32c3_kernel.o esp32c3_kernel.s
	$(RV_LD) $(RV_LDFLAGS) -o build/release/esp32c3_kernel.elf build/release/esp32c3_kernel.o
	$(RV_OBJ) -O binary build/release/esp32c3_kernel.elf build/release/esp32c3_kernel.bin
	rm -f build/release/esp32c3_kernel.o build/release/esp32c3_kernel.elf
	ln -sf release/esp32c3_kernel.bin esp32c3_kernel.bin

# ---------------------------------------------------------------------
# DEBUG TARGET (Includes ELF, Map files, and Disassembly listings)
# ---------------------------------------------------------------------
debug: build/debug/esp32c3_kernel.bin build/debug/esp32c3_kernel.lst
	@echo "[BUILD] Debug kernel build completed in build/debug/"

build/debug/esp32c3_kernel.bin: esp32c3_kernel.s esp32c3_kernel_linker.ld
	mkdir -p build/debug
	$(RV_AS) $(RV_ASFLAGS) -g -o build/debug/esp32c3_kernel.o esp32c3_kernel.s
	$(RV_LD) $(RV_LDFLAGS) -Map build/debug/esp32c3_kernel.map -o build/debug/esp32c3_kernel.elf build/debug/esp32c3_kernel.o
	$(RV_OBJ) -O binary build/debug/esp32c3_kernel.elf build/debug/esp32c3_kernel.bin
	ln -sf debug/esp32c3_kernel.bin esp32c3_kernel.bin
	rm -f build/debug/esp32c3_kernel.o

build/debug/esp32c3_kernel.lst: build/debug/esp32c3_kernel.elf
	$(RV_DUMP) -D build/debug/esp32c3_kernel.elf > build/debug/esp32c3_kernel.lst

clean:
	rm -rf build/release/esp32c3_kernel* build/debug/esp32c3_kernel* esp32c3_kernel.bin
