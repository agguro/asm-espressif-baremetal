# ESP32-C3 Bare-Metal Host Loader & Kernel Pipeline

A zero-dependency, pure assembly deployment pipeline designed to boot custom RISC-V bare-metal kernels directly onto an ESP32-C3 microcontroller from an x86_64 Linux host. This project bypasses traditional tooling like Python and `esptool.py`, communicating directly with the ROM bootloader via native Linux system calls, SLIP packet framing, and custom USB-JTAG reset sequences.

---

## Features

* **Pure Assembly Architecture:** Written entirely in x86_64 GNU Assembler (`as`) for the host and RISC-V assembly for the target kernel.
* **Zero Runtime Dependencies:** Requires no Python environments, complex toolchains, or heavy C/C++ runtime libraries.
* **Symlink-Based Deployment:** Automatically links a root-level `esp32c3_kernel.bin` symlink to whatever active binary is built inside the `build/` directory.
* **Robust SLIP Protocol & Escaping:** Features built-in binary escaping to handle raw payload bytes safely without breaking ROM-bootloader framing.
* **Dynamic Checksum Calculation:** Calculates live XOR checksums over the kernel binary at runtime.
* **Native USB-JTAG Reset Handling:** Replicates the exact state-machine timing of DTR and RTS signals to force the ESP32-C3 into download mode reliably.

---

## Project Structure├── esp32c3_host.s         # x86_64 host loader & serial monitor
├── esp32c3_kernel.s       # RISC-V bare-metal kernel (e.g., LED blink)
├── stub.ld                # RISC-V linker script for SRAM execution
├── Makefile               # Automated build pipeline
└── build/                 # Generated object files, ELFs, and raw binaries---

## Pros and Cons

### Pros (Advantages)
* **Blazing Fast & Lightweight:** Because it uses direct Linux system calls (`sys_open`, `sys_write`, `sys_read`, `sys_nanosleep`), the host tool compiles into a tiny, lightning-fast binary.
* **Deep Hardware Understanding:** Total transparency over every byte sent across the serial wire, offering ultimate control over memory addresses, watchdogs, and GPIO registers.
* **Independent & Portable:** No bloated SDKs to install or maintain. As long as you have GNU Binutils and a Linux system, it builds instantly.
* **Modular Design:** The host loader acts as a universal deployment pipe, allowing you to swap out kernels via simple symlinks (`esp32c3_kernel.bin`) effortlessly.

### Cons (Disadvantages)
* **SRAM-Only (Volatile):** Kernels are loaded directly into volatile RAM (`0x40380000`). Powering down or resetting the board clears the program (it does not flash permanent SPI Flash by default).
* **Platform-Dependent:** The host loader relies on x86_64 Linux system calls and TTY IOCTL structures, meaning it won't run natively on Windows or macOS without modification.
* **Manual Low-Level Management:** No safety nets—writing incorrect memory bounds, missing watchdog termination routines, or messing up stack pointers in your kernel will crash the microcontroller immediately.
* **Hardcoded Device Paths:** Currently bound to static device nodes (e.g., `/dev/ttyACM0`), requiring manual updates if Linux shuffles your serial ports.

---

## Quick Start

1. **Build and Run:**
   `make run`
2. **Trace System Calls (Debug Mode):**
   `make trace`
3. **Clean Build Artifacts:**
   `make clean`

---

## License

This project is open-source software licensed under the **Apache License 2.0**. See the `LICENSE` file for details.
