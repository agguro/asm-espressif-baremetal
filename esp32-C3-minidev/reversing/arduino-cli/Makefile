# =====================================================================
# Generieke Makefile voor arduino-cli & Reverse Engineering
# =====================================================================

# Configuratie (pas aan naar wens of overschrijf via de command line)
TARGET ?= sketch_name
FQBN   ?= esp32:esp32:esp32c3
PORT   ?= /dev/ttyACM0
BUILD  ?= build

# Bepaal de juiste toolchain op basis van de architecture (voor objdump/reversen)
# Voor ESP32-C3 (RISC-V) gebruik je de riscv toolchain
OBJDUMP ?= riscv64-unknown-elf-objdump

.PHONY: all compile clean disasm info

all: compile

# Compileer de schets en plaats alle output direct in de build/ folder
compile:
	@mkdir -p $(BUILD)
	arduino-cli compile --fqbn $(FQBN) --output-dir $(BUILD) $(TARGET)
	cp $(TARGET)/$(TARGET).ino $(BUILD)/
	
# Genereer een volledige assembly-listing van de ELF voor analyse in Ghidra/Radare2
disasm: compile
	@if [ -f $(BUILD)/$(TARGET).ino.elf ]; then \
		$(OBJDUMP) -d $(BUILD)/$(TARGET).ino.elf > $(BUILD)/$(TARGET).asm; \
		echo "[+] Disassembly opgeslagen in $(BUILD)/$(TARGET).asm"; \
	else \
		echo "[-] ELF bestand niet gevonden in $(BUILD)/"; \
	fi

# Upload de binair naar het board
upload: compile
	arduino-cli upload -p $(PORT) --fqbn $(FQBN) $(TARGET)

# Toon board enpoorten info
info:
	arduino-cli board list

# Schoon de build-map op
clean:
	rm -rf $(BUILD)
