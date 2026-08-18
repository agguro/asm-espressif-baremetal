=====================================================================
Project:     Bare-Metal ESP32-C3 Host Loader (Native USB-JTAG)
Name:        esp32c3_host.s
Author:      agguro
Date:        August 18, 2026
=====================================================================

## What It Does
`esp32c3_host.s` is a standalone, dependency-free x86_64 host tool written in pure GNU Assembly (`as`). It interfaces directly with an ESP32-C3 microcontroller over a serial/USB connection using native Linux system calls, without relying on standard C libraries (like glibc). 

The program automates the complete bootstrap sequence required to boot a RISC-V target:
1. **Command-Line Parsing:** Dynamically parses arguments to accept custom serial ports (`-p`) and external kernel binary paths.
2. **File Ingestion:** Attempts to load a specified kernel binary (`esp32c3_kernel.bin`) from disk into memory. If the file is missing, it seamlessly falls back to a **fully embedded fallback binary** compiled directly into the executable's data section.
3. **Hardware Reset & Configuration:** Toggles serial control lines (DTR and RTS) via `ioctl` to trigger a hardware reset and force the ESP32-C3 into its built-in serial bootloader mode, configuring the host serial port to raw binary mode at 115200 baud.
4. **Bootloader Handshake:** Establishes communication by exchanging synchronization packets, attaching SPI peripherals, and dynamically allocating SRAM space on the target chip.
5. **SLIP-Escaped Upload:** Formats and streams the kernel payload using Serial Line Internet Protocol (SLIP) framing and checksum calculation.
6. **Execution & Clean Exit:** Triggers the jump vector to hand over control to the RISC-V kernel, then closes the serial port and exits cleanly and immediately.

---

## Key Features
* **Zero Dependencies:** Pure x86_64 assembly utilizing direct Linux system calls (`sys_open`, `sys_read`, `sys_write`, `sys_ioctl`, `sys_nanosleep`, `sys_exit`).
* **Embedded Fallback Kernel:** Features a fully compiled, standalone RISC-V blink and watchdog-disabling routine (`fallback_bin`) embedded right inside the binary, ensuring the loader can function even if external files are absent.
* **Flexible CLI Argument Parsing:** Robust argument handling supporting multiple flag orders (e.g., `esp32c3_host -p /dev/ttyACM1 kernel.bin` or `esp32c3_host kernel.bin -p /dev/ttyACM1`).
* **Native USB-JTAG Reset Logic:** Precise modem-line bit toggling (`TIOCMBIS` / `TIOCMBIC`) to manage DTR and RTS lines for automated bootloader entry.
* **SLIP Framing & Checksum Protection:** Implements SLIP packet encapsulation (`0xC0` boundaries and `0xDB` byte escaping) along with custom checksum validation (`0xEF` seed XOR accumulation) to guarantee reliable data transmission over serial lines.
* **Immediate Clean Exit:** Closes the serial port and exits program execution instantly after the kernel handoff, allowing immediate transition to external debugging tools like OpenOCD and GDB.

---

## Copyright & License Notice

Copyright 2026 agguro

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
