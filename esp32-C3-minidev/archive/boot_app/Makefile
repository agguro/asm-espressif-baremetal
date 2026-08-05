# ==============================================================================
# Makefile for ESP32-C3 (RISC-V) OTA Boot Sector
# ==============================================================================

# Toolchain definitions
AS      = riscv32-esp-elf-as
OBJCOPY = riscv32-esp-elf-objcopy
ESPTOOL = esptool

# Flashing parameters
PORT       = /dev/ttyACM0
BAUD       = 921600
FLASH_ADDR = 0xe000

# Files
SRC = boot_app.s
OBJ = boot_app.o
BIN = boot_app.bin

# Default target
.PHONY: all clean flash

all: $(BIN)

# Step 1: Assemble to object file
$(OBJ): $(SRC)
	$(AS) -o $@ $<

# Step 2: Extract raw binary
$(BIN): $(OBJ)
	$(OBJCOPY) -O binary $< $@

# Step 3: Flash to ESP32-C3
flash: $(BIN)
	$(ESPTOOL) --chip esp32c3 --port $(PORT) --baud $(BAUD) write-flash $(FLASH_ADDR) $(BIN)

# Cleanup
clean:
	rm -f $(OBJ) $(BIN)
