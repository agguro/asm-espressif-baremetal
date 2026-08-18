# =====================================================================
# Project:    Bare-Metal ESP32-C3 Host Loader Build System
# Target:     $(TARGET)
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

# -ahls=... generates the listing file using the stem ($*) of the filename
HOST_ASFLAGS_DBG = --64 -g -ahls=$(BUILD_DBG)/$*.lst
HOST_LDFLAGS_DBG = -Map $(BUILD_DBG)/$(TARGET).map

# ---------------------------------------------------------------------
# AUTOMATIC FILE DISCOVERY
# ---------------------------------------------------------------------
# Find all .s files in the folder
TEST_SRCS     = $(wildcard *.s)

# Create lists of what the .o files SHOULD be named inside the build folders
TEST_OBJS_REL = $(patsubst %.s,$(BUILD_REL)/%.o,$(TEST_SRCS))
TEST_OBJS_DBG = $(patsubst %.s,$(BUILD_DBG)/%.o,$(TEST_SRCS))

.PHONY: all release debug test run trace clean

# Default target when you just type "make"
all: release debug

# ---------------------------------------------------------------------
# INDIVIDUAL BUILD TARGETS
# ---------------------------------------------------------------------
release: $(BUILD_REL)/$(TARGET)_test

debug: $(BUILD_DBG)/$(TARGET)_test

test: release debug

# Ensure build directories exist
$(BUILD_REL) $(BUILD_DBG):
	mkdir -p $@

# ---------------------------------------------------------------------
# RELEASE BUILD PIPELINE
# ---------------------------------------------------------------------
# 1. Link all object files ($^) into the final executable
$(BUILD_REL)/$(TARGET)_test: $(TEST_OBJS_REL) | $(BUILD_REL)
	$(HOST_LD) $(HOST_LDFLAGS_REL) -o $@ $^

# 2. Pattern Rule: How to turn ANY .s file into a release .o file
$(BUILD_REL)/%.o: %.s | $(BUILD_REL)
	$(HOST_AS) $(HOST_ASFLAGS_REL) -o $@ $<

# ---------------------------------------------------------------------
# DEBUG BUILD PIPELINE
# ---------------------------------------------------------------------
# 1. Link all object files ($^) into the final executable
$(BUILD_DBG)/$(TARGET)_test: $(TEST_OBJS_DBG) | $(BUILD_DBG)
	$(HOST_LD) $(HOST_LDFLAGS_DBG) -o $@ $^

# 2. Pattern Rule: How to turn ANY .s file into a debug .o file
$(BUILD_DBG)/%.o: %.s | $(BUILD_DBG)
	$(HOST_AS) $(HOST_ASFLAGS_DBG) -o $@ $<

# ---------------------------------------------------------------------
# UTILITY TARGETS
# ---------------------------------------------------------------------
test: $(BUILD_REL)/$(TARGET)_test
	@echo "========================================================="
	@echo " Executing Assembly Tool..."
	@./$(BUILD_REL)/$(TARGET)_test $(TARGET).s; \
	ASM_EXIT=$$?; \
	ASM_HEX=$$(printf "0x%02X" $$ASM_EXIT); \
	GAWK_HEX=$$(od -An -v -t u1 $(TARGET).s | gawk 'BEGIN{c=239} {for(i=1;i<=NF;i++) c=xor(c, $$i)} END{printf "0x%02X", c}'); \
	echo "---------------------------------------------------------"; \
	echo " Assembly Exit Code : $$ASM_HEX"; \
	echo " GNU Awk Output     : $$GAWK_HEX"; \
	if [ "$$ASM_HEX" = "$$GAWK_HEX" ]; then \
		echo "---------------------------------------------------------"; \
		echo " [SUCCESS] Checksums MATCH perfectly!"; \
		echo "========================================================="; \
	else \
		echo "---------------------------------------------------------"; \
		echo " [ERROR] Checksum MISMATCH!"; \
		echo "========================================================="; \
		exit 1; \
	fi

trace: $(BUILD_REL)/$(TARGET)_test
	@strace ./$(BUILD_REL)/$(TARGET)_test $(TARGET).s; true

clean:
	rm -rf $(BUILD_ROOT)/
