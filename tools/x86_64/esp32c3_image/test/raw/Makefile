# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly
# Author:      agguro
# Date:        August 11, 2026
# Description: Automated build, python patch, and flash pipeline 
#              using the generic Debian riscv64-unknown-elf toolchain.
# =====================================================================

TARGET      ?= $(shell basename $(CURDIR))
PORT        ?= /dev/ttyACM0
OUT         ?= build

ELF         ?= $(OUT)/$(TARGET).elf
BIN         ?= $(OUT)/$(TARGET).bin
OBJ         ?= $(OUT)/$(TARGET).o
LST         ?= $(OUT)/$(TARGET).lst
SRC         ?= $(TARGET).s

RV_AS       = riscv64-unknown-elf-as
RV_LD       = riscv64-unknown-elf-ld
RV_OBJ      = riscv64-unknown-elf-objcopy
ESPTOOL     = esptool

RV_ASFLAGS  = -march=rv32imc_zicsr -mabi=ilp32
RV_LDFLAGS  = -m elf32lriscv -Ttext=0x40380000

.PHONY: all build erase flash clean

all: build

build: $(BIN)

$(OBJ): $(SRC)
	@mkdir -p $(OUT)
	$(RV_AS) $(RV_ASFLAGS) -alh -o $@ $< > $(LST)

$(ELF): $(OBJ)
	$(RV_LD) $(RV_LDFLAGS) -o $@ $<

$(BIN): $(ELF)
	$(RV_OBJ) -O binary -j .text $< $@

erase:
	$(ESPTOOL) --port $(PORT) --chip esp32c3 erase-flash

flash: build
	$(ESPTOOL) --port $(PORT) --chip esp32c3 write-flash 0x0 $(BIN)

clean:
	rm -rf $(OUT)
