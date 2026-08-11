TARGET  = usb_echo
OUT     = build

CC      = riscv32-esp-elf-gcc
OBJCOPY = riscv32-esp-elf-objcopy
ESPTOOL = esptool
PORT    ?= /dev/ttyACM0

all: $(OUT)/$(TARGET).bin

$(OUT)/$(TARGET).elf: main.c linker.ld
	@mkdir -p $(OUT)
	$(CC) -march=rv32imc -O2 -nostdlib -nostartfiles -T linker.ld -o $@ $<

$(OUT)/$(TARGET).bin: $(OUT)/$(TARGET).elf
	$(OBJCOPY) -O binary -j .text -j .rodata -j .data $< $@
	@python3 -c 'import sys, functools, operator; path = "$(OUT)/$(TARGET).bin"; raw = bytearray(open(path, "rb").read()); header = bytearray([0xE9, 1, 2, 0, 0x00, 0x00, 0x38, 0x40, 0x00, 0x00, 0x00, 0x00, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]); seg_len = len(raw); seg_len_bytes = seg_len.to_bytes(4, "little"); segment_header = seg_len_bytes + seg_len_bytes; payload = header + segment_header + raw; pad_len = (15 - (len(payload) % 16)) % 16; payload.extend(b"\x00" * pad_len); chk = functools.reduce(operator.xor, payload[32:], 0xEF); payload.append(chk); open(path, "wb").write(payload); print("Build succesvol!")'

flash: all
	$(ESPTOOL) --port $(PORT) --chip esp32c3 write-flash 0x0 $(OUT)/$(TARGET).bin

clean:
	rm -rf $(OUT)
