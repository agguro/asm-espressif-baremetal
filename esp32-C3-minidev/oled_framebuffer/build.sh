#!/bin/bash
set -e

TARGET=$(basename $PWD)
OUT="build"
ELF="$OUT/$TARGET.elf"
BIN="$OUT/$TARGET.bin"
OBJ="$OUT/$TARGET.o"
LST="$OUT/$TARGET.lst"

mkdir -p "$OUT" dump

echo "[0] Erasing chip"
esptool --port /dev/ttyACM0 --chip esp32c3 erase-flash

echo "[1] Assembling..."
riscv32-esp-elf-as -march=rv32imc -alh -o "$OBJ" "$TARGET.s" > "$LST"

echo "[2] Linking ..."
riscv32-esp-elf-ld -Ttext=0x40380000 -o "$ELF" "$OBJ"

echo "[3] Extracting raw binary..."
riscv32-esp-elf-objcopy -O binary -j .text "$ELF" "$BIN"

echo "[4, 5 & 6] Patching length and checksum..."
python3 -c '
import sys
with open(sys.argv[1], "rb") as f:
    data = bytearray(f.read())

seg_len = len(data) - 32
data[28:32] = seg_len.to_bytes(4, "little")

pad_len = (15 - (len(data) % 16)) % 16
data.extend(b"\x00" * pad_len)

chk = 0xEF
for b in data[32:]:
    chk ^= b
data.append(chk)

with open(sys.argv[1], "wb") as f:
    f.write(data)
' "$BIN"

echo "[7] Flashing..."
esptool --chip esp32c3 write-flash 0x0 "$BIN"
