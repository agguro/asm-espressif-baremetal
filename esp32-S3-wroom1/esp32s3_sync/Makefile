# =====================================================================
# Project:     $(shell basename $(CURDIR))
# Description: x86_64 Host Assembly Build Pipeline
# =====================================================================

TARGET  ?= $(shell basename $(CURDIR))
OUT     ?= build
SRC     ?= $(TARGET).s
OBJ     ?= $(OUT)/$(TARGET).o
EXE     ?= $(OUT)/$(TARGET)

AS      = as
LD      = ld
ASFLAGS = --64
LDFLAGS = -s

.PHONY: all run trace clean

all: $(EXE)

$(OUT):
	mkdir -p $(OUT)

$(OBJ): $(SRC) | $(OUT)
	$(AS) $(ASFLAGS) -o $@ $<

$(EXE): $(OBJ)
	$(LD) $(LDFLAGS) -o $@ $<

run: $(EXE)
	sudo ./$(EXE)

trace: $(EXE)
	sudo strace ./$(EXE)

clean:
	rm -rf $(OUT)
