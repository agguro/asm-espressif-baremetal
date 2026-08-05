# ==============================================================================
# Makefile for ESP32-C3 minimal project with custom OTA boot_app0
# ==============================================================================

PROJECT = minimal
FQBN    = esp32:esp32:esp32c3
PORT    = /dev/ttyACM0
BAUD    = 921600

# Binaries to flash
BOOTLOADER = ./build/$(PROJECT).ino.bootloader.bin
PARTITIONS = ./build/$(PROJECT).ino.partitions.bin
APP        = ./build/$(PROJECT).ino.bin

# Your custom bare-metal OTA boot app (ensure this file exists in your project root)
CUSTOM_BOOT_APP = ./build/boot_app.bin

.PHONY: all compile upload clean

all: compile

compile:
	arduino-cli compile --fqbn $(FQBN) --build-path ./build .
	cp ../boot_app/boot_app.bin build/
upload:
	esptool --chip esp32c3 --port $(PORT) --baud $(BAUD) write_flash \
		0x00000 $(BOOTLOADER) \
		0x08000 $(PARTITIONS) \
		0x0e000 $(CUSTOM_BOOT_APP) \
		0x10000 $(APP)

clean:
	rm -rf ./build
