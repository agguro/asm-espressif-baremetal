# =====================================================================
# Project:     Bare-Metal ESP32-C3 Host Loader Build System
# Target:      $(TARGET)
# =====================================================================

TARGET           = $(shell basename $(CURDIR))
HOST_AS          = as
HOST_LD          = ld

HOST_ASFLAGS_REL = --64
HOST_LDFLAGS_REL = -s

# Build directories
BUILD_ROOT       = build
BUILD_REL        = $(BUILD_ROOT)/release
BUILD_DBG        = $(BUILD_ROOT)/debug

# -ahls=... generates the listing file directly at assembly time
HOST_ASFLAGS_DBG = --64 -g -ahls=$(BUILD_DBG)/$(TARGET).lst
HOST_LDFLAGS_DBG = -Map $(BUILD_DBG)/$(TARGET).map

.PHONY: all release debug run trace clean

all: release

# Ensure build directories exist via order-only prerequisites
$(BUILD_REL) $(BUILD_DBG):
	mkdir -p $@

# ---------------------------------------------------------------------
# RELEASE TARGET
# ---------------------------------------------------------------------
release: $(BUILD_REL)/$(TARGET)
	
$(BUILD_REL)/$(TARGET): $(TARGET).s | $(BUILD_REL)
	$(HOST_AS) $(HOST_ASFLAGS_REL) -o $(BUILD_REL)/$(TARGET).o $<
	$(HOST_LD) $(HOST_LDFLAGS_REL) -o $@ $(BUILD_REL)/$(TARGET).o
	@rm -f $(BUILD_REL)/$(TARGET).o

# ---------------------------------------------------------------------
# DEBUG TARGET
# ---------------------------------------------------------------------
debug: $(BUILD_DBG)/$(TARGET)

$(BUILD_DBG)/$(TARGET): $(TARGET).s | $(BUILD_DBG)
	$(HOST_AS) $(HOST_ASFLAGS_DBG) -o $(BUILD_DBG)/$(TARGET).o $<
	$(HOST_LD) $(HOST_LDFLAGS_DBG) -o $@ $(BUILD_DBG)/$(TARGET).o
	@rm -f $(BUILD_DBG)/$(TARGET).o

# ---------------------------------------------------------------------
# UTILITY TARGETS
# ---------------------------------------------------------------------
run: release
	./$(BUILD_REL)/$(TARGET)

trace: release
	strace ./$(BUILD_REL)/$(TARGET)

clean:
	rm -rf $(BUILD_ROOT)/
