/* ==========================================================================
 * minimal.ld - Minimal Linker Script for bare-metal ESP32-C3
 * ========================================================================== */

ENTRY(_start)

MEMORY {
    /* ESP32-C3 Instruction RAM (IRAM) starting address and length */
    iram (rwx) : ORIGIN = 0x40380000, LENGTH = 0x60000
}

SECTIONS {
    .text : ALIGN(4) {
        *(.text*)
        *(.rodata*)
    } > iram
}
