# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly with Closed-Source Libraries
# Author:      agguro
# Date:        August 11, 2026
# Description: Automated build pipeline linking proprietary BT/Wi-Fi archives
# =====================================================================

TARGET  ?= $(shell basename $(CURDIR))
PORT    ?= /dev/ttyACM0
OUT     ?= build
LIB_DIR ?= ../../libs

ELF     ?= $(OUT)/$(TARGET).elf
BIN     ?= $(OUT)/$(TARGET).bin
OBJ     ?= $(OUT)/$(TARGET).o
LST     ?= $(OUT)/$(TARGET).lst
SRC     ?= $(TARGET).s

AS      = riscv32-esp-elf-as
LD      = riscv32-esp-elf-ld
OBJCOPY = riscv32-esp-elf-objcopy
OBJDUMP = riscv32-esp-elf-objdump
ESPTOOL = esptool

# Proprietary binary library archives
BT_LIBS   = $(LIB_DIR)/bluetooth/libbtdm_app.a $(LIB_DIR)/bluetooth/libbtdm_app_flash.a

.PHONY: all build dump erase flash clean

all: build

build: $(BIN)

$(OBJ): $(SRC)
	@mkdir -p $(OUT)
	$(AS) -march=rv32imc -alh -o $@ $< > $(LST)

# In het ELF-linkernummer:
$(ELF): $(OBJ) linker.ld
	$(LD) -T linker.ld -o $@ $< \
		--start-group $(BT_LIBS) --end-group

# In de OBJCOPY stap (neem alle essentiële laadbare secties mee):
$(BIN): $(ELF)
	$(OBJCOPY) -O binary -j .text -j .rodata -j .data $< $@
	@python3 -c 'import sys, functools, operator; \
path=sys.argv[1]; \
data=bytearray(open(path, "rb").read()); \
seg_len=len(data)-32; \
data[28:32]=seg_len.to_bytes(4, "little"); \
pad_len=(15-(len(data)%16))%16; \
data.extend(b"\x00"*pad_len); \
chk=functools.reduce(operator.xor, data[32:], 0xEF); \
data.append(chk); \
open(path, "wb").write(data)' $@

dump: $(ELF)
	$(OBJDUMP) -d $(ELF) > $(OUT)/$(TARGET).dump
	@echo "Disassembly written to $(OUT)/$(TARGET).dump"

erase:
	$(ESPTOOL) --port $(PORT) --chip esp32c3 erase-flash

flash: build
	$(ESPTOOL) --port $(PORT) --chip esp32c3 write-flash 0x0 $(BIN)

clean:
	rm -rf $(OUT)
