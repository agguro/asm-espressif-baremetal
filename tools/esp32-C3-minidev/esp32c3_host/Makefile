# =====================================================================
# Project:     Bare-Metal ESP32-C3 Host Loader Build System
# =====================================================================

HOST_AS = as
HOST_LD = ld

HOST_ASFLAGS_REL = --64
HOST_LDFLAGS_REL = -s

# -ahls=... generates the listing file at assembly time
HOST_ASFLAGS_DBG = --64 -g -ahls=build/debug/esp32c3_host.lst
HOST_LDFLAGS_DBG = -Map build/debug/esp32c3_host.map

.PHONY: all release debug run trace clean

all: release

# ---------------------------------------------------------------------
# RELEASE TARGET
# ---------------------------------------------------------------------
release: build/release/esp32c3_host
	tree build/release
	
build/release/esp32c3_host: esp32c3_host.s
	mkdir -p build/release
	$(HOST_AS) $(HOST_ASFLAGS_REL) -o build/release/esp32c3_host.o esp32c3_host.s
	$(HOST_LD) $(HOST_LDFLAGS_REL) -o build/release/esp32c3_host build/release/esp32c3_host.o
	rm -f build/release/esp32c3_host.o

# ---------------------------------------------------------------------
# DEBUG TARGET
# ---------------------------------------------------------------------
debug: build/debug/esp32c3_host
	@tree build/debug

build/debug/esp32c3_host: esp32c3_host.s
	mkdir -p build/debug
	$(HOST_AS) $(HOST_ASFLAGS_DBG) -o build/debug/esp32c3_host.o esp32c3_host.s
	$(HOST_LD) $(HOST_LDFLAGS_DBG) -o build/debug/esp32c3_host build/debug/esp32c3_host.o

# ---------------------------------------------------------------------
# UTILITY TARGETS
# ---------------------------------------------------------------------
run: release
	./build/release/esp32c3_host

trace: release
	strace ./build/release/esp32c3_host

clean:
	rm -rf build/
