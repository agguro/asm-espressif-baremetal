# =====================================================================
# Minimalist Makefile for Raw ATmega2560 Assembly
# =====================================================================

# Target file configuration
TARGET = blink
SRC = blink.s

# Toolchain definitions
AS = avr-as
LD = avr-ld
OBJCOPY = avr-objcopy
AVR_OBJDUMP = avr-objdump

# Hardware flashing configuration
# Note: Check if your port matches /dev/ttyACM0, /dev/ttyACM1, or /dev/ttyUSB0
PORT = /dev/ttyUSB0
BAUD = 115200
PROGRAMMER = wiring

# Architecture Flags
MCU_AS = atmega2560
MCU_LD = avr6

.PHONY: all clean flash dump

# Default target
all: $(TARGET).hex

# 1. Assemble to raw object file (forcing core architecture tier)
$(TARGET).o: $(SRC)
	$(AS) -mmcu=$(MCU_AS) -o $@ $<

# 2. Link to minimalist ELF binary with absolute custom start tracking
$(TARGET).elf: $(TARGET).o blink.ld
	$(LD) -m $(MCU_LD) -T blink.ld -o $@ $<

# 3. Flatten directly into standard Intel HEX syntax
$(TARGET).hex: $(TARGET).elf
	$(OBJCOPY) -O ihex -R .eeprom $< $@

# Flash the hex image raw to the serial port mapping
flash: $(TARGET).hex
	avrdude -v -p m2560 -c $(PROGRAMMER) -P $(PORT) -b $(BAUD) -D -U flash:w:$<:i

# Quick check target to read your flat opcode structure
dump: $(TARGET).elf
	$(AVR_OBJDUMP) -d $<

# Clean temporary tracking files
clean:
	rm -f *.o *.elf *.hex
