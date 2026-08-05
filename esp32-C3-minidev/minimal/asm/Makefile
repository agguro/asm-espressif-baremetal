# ==============================================================================
# Makefile for ESP32-C3 pure assembly project (True Bare-Metal)
# ==============================================================================

PORT = /dev/ttyACM0
BAUD = 921600

TARGET = minimal

AS      = riscv32-esp-elf-as
LD      = riscv32-esp-elf-ld
ESPTOOL = esptool

SRC = $(TARGET).s
LDS = $(TARGET).ld
OBJ = build/$(TARGET).o
ELF = build/$(TARGET).elf
APP = build/$(TARGET).bin

.PHONY: all clean flash

all: $(APP)

$(OBJ): $(SRC)
	@mkdir -p build
	$(AS) -o $@ $<

$(ELF): $(OBJ)
	$(LD) -T $(LDS) -o $@ $<

$(APP): $(ELF)
	$(ESPTOOL) --chip esp32c3 elf2image --flash-mode dio --flash-freq 40m --flash-size 4MB -o $@ $<

# We now flash our app directly to 0x00000, overwriting everything!
flash: $(APP)
	$(ESPTOOL) --chip esp32c3 --port $(PORT) --baud $(BAUD) write-flash \
		0x00000 $(APP)

clean:
	rm -rf build
