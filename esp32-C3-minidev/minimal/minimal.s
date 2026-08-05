# ==============================================================================
# minimal.s - True Bare-Metal ESP32-C3
# Strategy: Interrupts OFF, Watchdogs OFF, USB Transceiver FORCED ON
# ==============================================================================

.section .text
.align 4
.global _start

# --- Watchdog Registers ---
.equ TG0_WDT_PROTECT,  0x6001F064
.equ TG0_WDT_CONFIG0,  0x6001F048
.equ TG1_WDT_PROTECT,  0x60020064
.equ TG1_WDT_CONFIG0,  0x60020048
.equ RTC_WDT_PROTECT,  0x600080A8
.equ RTC_WDT_CONFIG0,  0x60008090
.equ SWD_WPROTECT,     0x600080B8
.equ SWD_CONF,         0x600080B4

# --- USB Serial/JTAG Register ---
.equ USB_SERIAL_JTAG_CONF0, 0x6004301C

# --- Magic Keys ---
.equ WDT_WKEY,         0x50D83AA1
.equ SWD_WKEY,         0x8F1D312A

_start:
    # 0. Block USB Interrupt Storms
    csrci mstatus, 8

    # 1. Safe Stack Pointer
    li   sp, 0x3FCE0000
    li   t2, 0x7FFFFFFF

    # 2. Disable TG0 Watchdog
    li   t0, TG0_WDT_PROTECT
    li   t1, WDT_WKEY
    sw   t1, 0(t0)
    li   t0, TG0_WDT_CONFIG0
    lw   t1, 0(t0)
    and  t1, t1, t2
    sw   t1, 0(t0)

    # 3. Disable TG1 Watchdog
    li   t0, TG1_WDT_PROTECT
    li   t1, WDT_WKEY
    sw   t1, 0(t0)
    li   t0, TG1_WDT_CONFIG0
    lw   t1, 0(t0)
    and  t1, t1, t2
    sw   t1, 0(t0)

    # 4. Disable RTC Watchdog
    li   t0, RTC_WDT_PROTECT
    li   t1, WDT_WKEY
    sw   t1, 0(t0)
    li   t0, RTC_WDT_CONFIG0
    lw   t1, 0(t0)
    and  t1, t1, t2
    sw   t1, 0(t0)

    # 5. Disable Super Watchdog (SWD)
    li   t0, SWD_WPROTECT
    li   t1, SWD_WKEY
    sw   t1, 0(t0)
    li   t0, SWD_CONF
    lw   t1, 0(t0)
    li   t3, 0x80000000
    or   t1, t1, t3
    sw   t1, 0(t0)

    # ----------------------------------------------------------------------
    # 6. FORCE USB PHY DISCONNECT
    # Instead of forcing it on, isolate the transceiver pads.
    # Pulling USB_PAD_ENABLE low or driving a manual pull-down prevents 
    # the Linux host from seeing the D+ line pull-up, stopping enumeration loops.
    # ----------------------------------------------------------------------
    li   t0, USB_SERIAL_JTAG_CONF0
    lw   t1, 0(t0)
    
    # Clear Bit 0 (USB_PAD_ENABLE) to detach the USB transceiver from the pins
    li   t2, ~0x1
    and  t1, t1, t2
    
    # Set Bit 1 (USB_PULLUP_EN) to 0 if needed to ensure no floating high state
    # or write 0 directly to clear all configuration overrides and float the lines.
    li   t1, 0 
    sw   t1, 0(t0)


    # 7. Safe Idle
hang:
    wfi
    j    hang
