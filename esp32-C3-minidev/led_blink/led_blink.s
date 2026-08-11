# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly led_blink
# Author:      agguro
# Date:        August 11, 2026
# Description: Pure assembly bare-metal led_blink on GPIO 8 for ESP32-C3
# =====================================================================

.section .text
.option norelax
. = 0                    # Start cleanly at 0 for the flat binary

    # ---------------------------------------------------------
    # ESP32-C3 ROM IMAGE HEADER V2 (24 bytes)
    # The ESP32-C3 bootloader reads this fixed header from flash 
    # to know how to validate and load the image into memory.
    # ---------------------------------------------------------
    .byte 0xE9               # 0x00: Magic byte for ESP boot image
    .byte 1                  # 0x01: Number of segments
    .byte 2                  # 0x02: SPI flash mode (2 = DIO)
    .byte 0                  # 0x03: SPI flash speed and size config
    .word 0x40380000         # 0x04: Entry point address in IRAM
    .word 0                  # 0x08: WP pin / drive settings
    .half 5                  # 0x0C: Chip ID (5 = ESP32-C3)
    .byte 0                  # 0x0E: Minimum chip revision
    .half 0                  # 0x0F: Min revision full
    .half 0                  # 0x11: Max revision full
    .half 0                  # 0x13: Reserved bytes
    .byte 0                  # 0x15: Append digest flag
    .byte 0, 0               # 0x16: Padding alignment bytes

    # ---------------------------------------------------------
    # SEGMENT HEADER (8 bytes)
    # Defines the destination memory region for the binary payload.
    # ---------------------------------------------------------
    .word 0x40380000         # 0x18: Target load address in Instruction RAM (IRAM)
    .word _seg_end - _seg_start  # 0x1C: Dynamic segment length calculation

    # ---------------------------------------------------------
    # SEGMENT DATA (Main Entry Point)
    # ---------------------------------------------------------
    .global _start
_seg_start:
_start:
    # ---------------------------------------------------------
    # 1. CPU & ENVIRONMENT INITIALIZATION
    # ---------------------------------------------------------
    # Block/disable all CPU interrupts during early boot setup
    csrci mstatus, 8

    # Set up the Stack Pointer (sp) to a safe RAM boundary
    li   sp, 0x3FCE0000
    li   t2, 0x7FFFBBFF      # Bitmask used to clear watchdog write-protect bits

    # ---------------------------------------------------------
    # 2. WATCHDOG TIMER (WDT) & DEBUG DISABLE
    # Bare-metal code has no OS/FreeRTOS running, so we must disable 
    # all watchdogs immediately to prevent automatic hardware resets.
    # ---------------------------------------------------------
    
    # Disable Timer Group 0 (TG0) Watchdog
    li   t0, 0x6001F064      # WDT wprotect register
    li   t1, 0x50D83AA1      # Unlock magic key
    sw   t1, 0(t0)
    li   t0, 0x6001F048      # WDT config register
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable Timer Group 1 (TG1) Watchdog
    li   t0, 0x60020064      # WDT wprotect register
    sw   t1, 0(t0)
    li   t0, 0x60020048      # WDT config register
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable RTC Watchdog
    li   t0, 0x600080A8      # RTC WDT wprotect register
    sw   t1, 0(t0)
    li   t0, 0x60008090      # RTC WDT config register
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable Serial Wire Debug (SWD) / JTAG interference
    li   t0, 0x600080B8
    li   t1, 0x8F1D312A      # SWD unlock key
    sw   t1, 0(t0)
    li   t0, 0x600080B4
    lw   t3, 0(t0)
    li   t4, 0x80000000
    or   t3, t3, t4
    sw   t3, 0(t0)

    # Disconnect USB PHY to ensure clean standalone execution
    li   t0, 0x6004301C
    li   t3, 0
    sw   t3, 0(t0)

    # ---------------------------------------------------------
    # 3. GPIO CONFIGURATION (LED on GPIO 8)
    # ---------------------------------------------------------
    # Configure GPIO 8 as an output using the Write-1-to-Set (W1TS) enable register
    li   t0, 0x60004024      # GPIO_ENABLE_W1TS_REG
    li   t1, 0x100           # Bit 8 set high (1 << 8 = 256 / 0x100)
    sw   t1, 0(t0)

    # Cache register base addresses for fast bit manipulation in the loop
    li   s0, 0x60004008      # GPIO_OUT_W1TS_REG (Set GPIO pins HIGH)
    li   s1, 0x6000400C      # GPIO_OUT_W1TC_REG (Clear GPIO pins LOW)

    # ---------------------------------------------------------
    # 4. MAIN BLINK LOOP
    # ---------------------------------------------------------
blink_loop:
    # Phase A: Turn LED ON (Write bit 8 to Write-1-To-Set register)
    sw   t1, 0(s0)

    # Load delay count (ON period) using position-independent PC-relative addressing
.L_on:
    auipc a0, %pcrel_hi(delay_time)
    lw    t2, %pcrel_lo(.L_on)(a0)

delay_on:
    addi t2, t2, -1
    bnez t2, delay_on

    # Phase B: Turn LED OFF (Write bit 8 to Write-1-To-Clear register)
    sw   t1, 0(s1)

    # Load delay count (OFF period) using position-independent PC-relative addressing
.L_off:
    auipc a0, %pcrel_hi(delay_time)
    lw    t2, %pcrel_lo(.L_off)(a0)

delay_off:
    addi t2, t2, -1
    bnez t2, delay_off

    # Repeat endless loop
    j    blink_loop


# ---------------------------------------------------------
# 5. DATA SECTION (Constants & Variables)
# ---------------------------------------------------------
    .align 4
delay_time:
    .word 250000            # CPU cycle counter threshold for blink delay

_seg_end:
    .align 4
