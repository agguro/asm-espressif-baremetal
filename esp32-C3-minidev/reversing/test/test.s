# =====================================================================
# Project:     ESP32-C3 Bare-Metal Working UART Echo & LED (WDT Fixed)
# =====================================================================

.section .text
.option norelax
. = 0

    # ---------------------------------------------------------
    # ESP32-C3 ROM IMAGE HEADER V2 (24 bytes)
    # ---------------------------------------------------------
    .byte 0xE9, 1, 2, 0
    .word 0x40380000, 0
    .half 5
    .byte 0
    .half 0, 0, 0
    .byte 0, 0, 0

    # ---------------------------------------------------------
    # SEGMENT HEADER (8 bytes)
    # ---------------------------------------------------------
    .word 0x40380000
    .word _seg_end - _seg_start

.global _start
_seg_start:
_start:
    csrci mstatus, 8
    li   sp, 0x3FCE0000
    li   t2, 0x7FFFBBFF

    # --- WATCHDOGS UITSCHAKELEN ---
    li   t0, 0x6001F064
    li   t1, 0x50D83AA1
    sw   t1, 0(t0)
    li   t0, 0x6001F048
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    li   t0, 0x60020064
    sw   t1, 0(t0)
    li   t0, 0x60020048
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    li   t0, 0x600080A8
    sw   t1, 0(t0)
    li   t0, 0x60008090
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # --- SUPER WATCHDOG (SWD) UITSCHAKELEN ---
    li   t0, 0x600080B0        # RTC_CNTL_SWD_WPROTECT_REG
    li   t1, 0x50D83AA1
    sw   t1, 0(t0)
    li   t0, 0x600080AC        # RTC_CNTL_SWD_CONF_REG
    sw   zero, 0(t0)           # Schakel SWD uit om reboots te stoppen

    # --- GPIO 8 SETUP (LED UIT BIJ START) ---
    li   t0, 0x60004024        # GPIO_ENABLE_W1TS_REG
    li   t1, 0x100             # Bit 8 for GPIO 8
    sw   t1, 0(t0)

    li   t0, 0x60004008        # GPIO_OUT_W1TS_REG (Set High -> LED UIT)
    sw   t1, 0(t0)

    # =========================================================
    # MAIN UART0 ECHO & COMMAND LOOP
    # =========================================================
uart_loop:
    # 1. Check RX FIFO count in UART0_STATUS_REG (0x6000001C) [23:16]
    li   t0, 0x6000001C
.L_wait_rx:
    lw   t1, 0(t0)
    srli t1, t1, 16
    andi t1, t1, 0xFF
    beqz t1, .L_wait_rx

    # 2. Lees exact 1 woord uit UART0 FIFO (0x60000000)
    li   t3, 0x60000000
    lw   a1, 0(t3)
    andi a1, a1, 0xFF

    # 3. Controleer op commando '1' (LED AAN) of '0' (LED UIT)
    li   t4, '1'
    beq  a1, t4, cmd_on
    li   t4, '0'
    beq  a1, t4, cmd_off
    j    do_echo

cmd_on:
    li   t0, 0x6000400C       # GPIO_OUT_W1TC (Clear Low -> LED AAN)
    li   t1, 0x100
    sw   t1, 0(t0)
    j    do_echo

cmd_off:
    li   t0, 0x60004008       # GPIO_OUT_W1TS (Set High -> LED UIT)
    li   t1, 0x100
    sw   t1, 0(t0)

do_echo:
    # 4. Schrijf byte terug naar UART0 TX FIFO (0x60000000)
    li   t3, 0x60000000
    sw   a1, 0(t3)

    j    uart_loop

_seg_end:
    .align 4
