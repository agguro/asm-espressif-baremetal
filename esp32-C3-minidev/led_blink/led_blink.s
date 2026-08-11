.section .text
.option norelax
. = 0                    # Start netjes op 0 voor de platte binary

    # ---------------------------------------------------------
    # ESP32-C3 ROM IMAGE HEADER V2 (24 bytes)
    # ---------------------------------------------------------
    .byte 0xE9               # 0x00: Magic
    .byte 1                  # 0x01: Segment count
    .byte 2                  # 0x02: SPI mode
    .byte 0                  # 0x03: SPI speed/size
    .word 0x40380000         # 0x04: Entry point (IRAM)
    .word 0                  # 0x08: WP / drive config
    .half 5                  # 0x0C: Chip ID
    .byte 0                  # 0x0E: Min rev
    .half 0                  # 0x0F: Min rev full
    .half 0                  # 0x11: Max rev full
    .half 0                  # 0x13: Reserved
    .byte 0                  # 0x15: Append digest flag
    .byte 0, 0               # 0x16: Padding

    # ---------------------------------------------------------
    # SEGMENT HEADER (8 bytes)
    # ---------------------------------------------------------
    .word 0x40380000         # 0x18: Load address (IRAM)
    .word _seg_end - _seg_start  # 0x1C: Segment length

    # ---------------------------------------------------------
    # SEGMENT DATA
    # ---------------------------------------------------------
    .global _start
_seg_start:
_start:
    # Block interrupts
    csrci mstatus, 8

    # Stack
    li   sp, 0x3FCE0000
    li   t2, 0x7FFFBBFF

    # TG0 WDT
    li   t0, 0x6001F064
    li   t1, 0x50D83AA1
    sw   t1, 0(t0)
    li   t0, 0x6001F048
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # TG1 WDT
    li   t0, 0x60020064
    sw   t1, 0(t0)
    li   t0, 0x60020048
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # RTC WDT
    li   t0, 0x600080A8
    sw   t1, 0(t0)
    li   t0, 0x60008090
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # SWD
    li   t0, 0x600080B8
    li   t1, 0x8F1D312A
    sw   t1, 0(t0)
    li   t0, 0x600080B4
    lw   t3, 0(t0)
    li   t4, 0x80000000
    or   t3, t3, t4
    sw   t3, 0(t0)

    # USB PHY disconnect
    li   t0, 0x6004301C
    li   t3, 0
    sw   t3, 0(t0)

# ---------------------------------------------------------
# GPIO 8 BLINK SETUP
# ---------------------------------------------------------
    li   t0, 0x60004024      # GPIO_ENABLE_W1TS_REG
    li   t1, 0x100           # Bit 8 for GPIO 8
    sw   t1, 0(t0)

    li   s0, 0x60004008      # Set High
    li   s1, 0x6000400C      # Set Low

blink_loop:
    # 1. Turn LED ON
    sw   t1, 0(s0)

    # 2. Laad de delay waarde via PC-relatieve offset (%pcrel)
.L_on:
    auipc a0, %pcrel_hi(delay_time)
    lw    t2, %pcrel_lo(.L_on)(a0)

delay_on:
    addi t2, t2, -1
    bnez t2, delay_on

    # 3. Turn LED OFF
    sw   t1, 0(s1)

    # 4. Laad de delay waarde via PC-relatieve offset (%pcrel)
.L_off:
    auipc a0, %pcrel_hi(delay_time)
    lw    t2, %pcrel_lo(.L_off)(a0)

delay_off:
    addi t2, t2, -1
    bnez t2, delay_off

    # 5. Repeat
    j    blink_loop


# ---------------------------------------------------------
# DATA SECTIE (Variabele onderaan)
# ---------------------------------------------------------
    .align 4
delay_time:
    .word 250000            # De vertragingstijd

_seg_end:
    .align 4
