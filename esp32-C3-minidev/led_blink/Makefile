# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly
# Author:      agguro
# Date:        August 11, 2026
# Description: Automated build, python patch, and flash pipeline
# =====================================================================

TARGET  ?= $(shell basename $(CURDIR))
PORT    ?= /dev/ttyACM0
OUT     ?= build

ELF     ?= $(OUT)/$(TARGET).elf
BIN     ?= $(OUT)/$(TARGET).bin
OBJ     ?= $(OUT)/$(TARGET).o
LST     ?= $(OUT)/$(TARGET).lst
SRC     ?= $(TARGET).s

AS      ?= riscv32-esp-elf-as
LD      ?= riscv32-esp-elf-ld
OBJCOPY ?= riscv32-esp-elf-objcopy
ESPTOOL ?= esptool

.PHONY: all build erase flash clean

all: build

build: $(BIN)

# [1] Assembling
$(OBJ): $(SRC)
	@mkdir -p $(OUT)
	$(AS) -march=rv32imc -alh -o $@ $< > $(LST)

# [2] Linking
$(ELF): $(OBJ)
	$(LD) -Ttext=0x40380000 -o $@ $<

# [3, 4, 5 & 6] Extracting raw binary, padding and checksum patching
$(BIN): $(ELF)
	@echo "Extracting raw binary..."
	$(OBJCOPY) -O binary -j .text $< $@
	@echo "[4, 5 & 6] Patching length and checksum..."
	@python3 -c ' \
		import sys; \
		with open(sys.argv[1], "rb") as f: \
		    data = bytearray(f.read()); \
		seg_len = len(data) - 32; \
		data[28:32] = seg_len.to_bytes(4, "little"); \
		pad_len = (15 - (len(data) % 16)) % 16; \
		data.extend(b"\x00" * pad_len); \
		chk = 0xEF; \
		for b in data[32:]: \
		    chk ^= b; \
		data.append(chk); \
		with open(sys.argv[1], "wb") as f: \
		    f.write(data); \
		' $@

# [0] Erasing chip
erase:
	$(ESPTOOL) --port $(PORT) --chip esp32c3 erase-flash

# [7] Flashing
flash: erase build
	$(ESPTOOL) --port $(PORT) --chip esp32c3 write-flash 0x0 $(BIN)

# Cleanup
clean:
	rm -rf $(OUT)
