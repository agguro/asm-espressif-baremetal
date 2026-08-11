# =====================================================================
# Makefile met broncode-integratie in de disassembly
# =====================================================================

TARGET ?= bluetooth
FQBN   ?= esp32:esp32:esp32c3
PORT   ?= /dev/ttyACM0
BUILD  ?= build

OBJDUMP ?= riscv64-unknown-elf-objdump

.PHONY: all compile clean disasm upload

all: compile

compile:
	@mkdir -p $(BUILD)
	arduino-cli compile --fqbn $(FQBN) \
		--build-property "compiler.cpp.extra_flags=-g" \
		--build-property "compiler.c.extra_flags=-g" \
		--output-dir $(BUILD) .

disasm: compile
	@if [ -f $(BUILD)/$(TARGET).ino.elf ]; then \
		$(OBJDUMP) -d -S $(BUILD)/$(TARGET).ino.elf > $(BUILD)/$(TARGET).asm; \
		echo "[+] Assembly inclusief broncode opgeslagen in $(BUILD)/$(TARGET).asm"; \
	else \
		echo "[-] ELF bestand niet gevonden in $(BUILD)/"; \
	fi

upload: compile
	arduino-cli upload -p $(PORT) --fqbn $(FQBN) --input-dir $(BUILD)/ .

clean:
	rm -rf $(BUILD)
