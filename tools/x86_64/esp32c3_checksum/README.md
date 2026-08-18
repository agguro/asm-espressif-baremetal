# ESP32-C3 Vectorized Checksum Utility (x86_64)

A bare-metal, pure x86_64 assembly utility designed to calculate and verify the ESP32-C3 XOR bootloader checksum (Seed: `0xEF`). Built for ultimate performance and reliability, this tool utilizes 128-bit SSE hardware vectorization, a completely `.bss`-free register architecture, and strict System V AMD64 ABI compliance with zero C library dependencies.

## Architecture

The project is structured into standalone, reusable object files:

*   **`esp32c3_checksum.s`**: The core vectorized library. Uses `pxor` and XMM registers to process memory-mapped file data in parallel 16-byte chunks. Safe padding inherently handles trailing byte remainders.
*   **`bin2hexascii_uint8.s`**: A highly optimized, branchless math routine to convert binary values to hex-ASCII characters.
*   **`esp32c3_checksum_test.s`**: The CLI test harness wrapper. Handles argument parsing, file memory-mapping via Linux syscalls, and passes the 8-bit checksum back as the process exit code.

## Features
*   **Zero Dependencies:** No C Standard Library (`libc`) required.
*   **PIE/Linker Proof:** Immune to Position Independent Executable memory mapping bugs by relying strictly on RIP-relative addressing and register-driven I/O.
*   **Security:** Stack execution explicitly disabled via `.note.GNU-stack`.
*   **Automation Ready:** Designed to integrate cleanly into larger host build pipelines (like the upcoming `xf` flashtool).

## Building

A flexible `Makefile` is provided to handle both optimized release builds and debug configurations with automatic symbol listing generation:

```bash
# Build both release and debug test binaries
make

# Build strictly the optimized release version
make release

# Build strictly the debug version (generates .lst and .map files)
make debug

# test this program against gawk using the source file esp32c3_checksum.s 
make test
