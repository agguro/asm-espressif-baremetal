.section .text
.option norelax
. = 0                    # Start cleanly at 0 for the flat binary

    # ---------------------------------------------------------
    # ESP32-C3 ROM IMAGE HEADER V2 (24 bytes)
    # ---------------------------------------------------------
    .byte 0xE9               # 0x00: Magic
    .byte 1                  # 0x01: Segment count
    .byte 2                  # 0x02: SPI mode (2 = DIO)
    .byte 0                  # 0x03: SPI speed/size
    .word 0x40380000         # 0x04: Entry point (IRAM)
    .word 0                  # 0x08: WP / drive config
    .half 5                  # 0x0C: Chip ID (ESP32-C3 = 5)
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

    # Disable all Watchdogs (TG0, TG1, RTC) + SWD
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

    li   t0, 0x600080B8
    li   t1, 0x8F1D312A
    sw   t1, 0(t0)
    li   t0, 0x600080B4
    lw   t3, 0(t0)
    li   t4, 0x80000000
    or   t3, t3, t4
    sw   t3, 0(t0)

    # ---------------------------------------------------------
    # 1. CONFIGURE GPIO PINS FOR I2C (OPEN-DRAIN & PULL-UP)
    # SDA = 5, SCL = 6, LED = 8
    # ---------------------------------------------------------
    li   t0, 0x60009018      # IO_MUX_GPIO5_REG
    li   t1, (1 << 12) | (1 << 8)
    sw   t1, 0(t0)
    li   t0, 0x6000901C      # IO_MUX_GPIO6_REG
    sw   t1, 0(t0)

    li   t0, 0x60004088      # GPIO_PIN5_REG
    li   t1, (1 << 2)
    sw   t1, 0(t0)
    li   t0, 0x6000408C      # GPIO_PIN6_REG
    sw   t1, 0(t0)

    li   t0, 0x60004020      # GPIO_ENABLE_REG
    li   t1, (1 << 5) | (1 << 6) | (1 << 8)
    sw   t1, 0(t0)

    li   s0, 0x60004008      # W1TS
    li   s1, 0x6000400C      # W1TC
    li   t1, (1 << 5) | (1 << 6)
    sw   t1, 0(s0)

    li   t5, 500000
.L_boot_delay:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_boot_delay


    # ---------------------------------------------------------
    # 2. INITIALIZE SSD1306 OLED DISPLAY
    # ---------------------------------------------------------
.L_init_display:
    la   s4, ssd1306_init_cmds
    li   s5, 25

.L_init_loop:
    beqz s5, .L_start_vscroller
    lbu  a0, 0(s4)
    jal  ssd1306_send_cmd
    addi s4, s4, 1
    addi s5, s5, -1
    j    .L_init_loop


# ---------------------------------------------------------
# 3. VERTICAL SCROLLER MAIN APPLICATION
# ---------------------------------------------------------
.L_start_vscroller:
    jal  fb_clear
    
    # Initialize scroll position to 0
    la   t0, v_scroll_pos
    sw   zero, 0(t0)

vscroll_loop:
    # Turn LED on (active low on W1TC = 400C)
    li   t1, 0x100
    sw   t1, 0(s1)

    jal  v_scroll_step
    jal  fb_flush

    # Turn LED off
    sw   t1, 0(s0)

    # Frame delay (animation speed)
    li   t5, 35000
.L_vscroll_d:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_vscroll_d

    j    vscroll_loop


# ---------------------------------------------------------
# V_SCROLL_STEP: Shifts framebuffer up by 1 pixel and injects bottom row via zero-copy index
# ---------------------------------------------------------
v_scroll_step:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s2, 8(sp)
    sw   s3, 4(sp)

    la   t0, v_scroll_pos
    lw   s2, 0(t0)           # s2 = current text row index (zero-copy pointer offset)

    li   s3, 0               # Column loop X (0 to 71)

.L_v_col_loop:
    # 1. Load the 5 page bytes for column s3 from the framebuffer
    la   t0, framebuffer
    add  t1, t0, s3          # B0 (Page 0)
    addi t2, t1, 72          # B1 (Page 1)
    addi t3, t2, 72          # B2 (Page 2)
    addi t4, t3, 72          # B3 (Page 3)
    addi t5, t4, 72          # B4 (Page 4)

    lbu  a3, 0(t1)
    lbu  a4, 0(t2)
    lbu  a5, 0(t3)
    lbu  a6, 0(t4)
    lbu  a7, 0(t5)

    # 2. Fetch pixel from v_text_source at row s2 for the bottom screen edge
    li   t4, 9
    mul  t5, s2, t4          # Row byte offset (s2 * 9 bytes per row)

    srli t0, s3, 3           # byte_idx = X / 8
    andi t1, s3, 7           # bit_idx = X % 8

    # Correct horizontal bit order (MSB-first extraction)
    li   t3, 7
    sub  t1, t3, t1          # t1 = 7 - (X % 8)

    la   t6, v_text_source
    add  t6, t6, t5          # Base of source row s2
    add  t6, t6, t0          # + byte_idx
    lbu  t6, 0(t6)

    srl  t6, t6, t1
    andi t6, t6, 1           # New pixel bit (0 or 1)

    # 3. Shift the 40-bit column 1 pixel upwards
    srli a3, a3, 1
    andi t0, a4, 1
    slli t0, t0, 7
    or   a3, a3, t0

    srli a4, a4, 1
    andi t0, a5, 1
    slli t0, t0, 7
    or   a4, a4, t0

    srli a5, a5, 1
    andi t0, a6, 1
    slli t0, t0, 7
    or   a5, a5, t0

    srli a6, a6, 1
    andi t0, a7, 1
    slli t0, t0, 7
    or   a6, a6, t0

    srli a7, a7, 1
    slli t6, t6, 7          # Inject new pixel into bit 7 of Page 4 (bottom row Y = 39)
    or   a7, a7, t6

    # 4. Write back updated bytes to RAM framebuffer
    la   t0, framebuffer
    add  t1, t0, s3
    addi t2, t1, 72
    addi t3, t2, 72
    addi t4, t3, 72
    addi t5, t4, 72

    sb   a3, 0(t1)
    sb   a4, 0(t2)
    sb   a5, 0(t3)
    sb   a6, 0(t4)
    sb   a7, 0(t5)

    addi s3, s3, 1
    li   t0, 72
    bne  s3, t0, .L_v_col_loop

    # 5. Increment scroll position and wrap around at exact total row count (40 rows)
    la   t0, v_scroll_pos
    lw   s2, 0(t0)
    addi s2, s2, 1
    li   t1, 40              # Total height of v_text_source in rows
    bne  s2, t1, .L_v_pos_save
    li   s2, 0
.L_v_pos_save:
    sw   s2, 0(t0)

    lw   s3, 4(sp)
    lw   s2, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret


# ---------------------------------------------------------
# FRAMEBUFFER ROUTINES
# ---------------------------------------------------------
fb_clear:
    la   t0, framebuffer
    li   t1, 360
    li   t3, 0
.L_clr_l:
    sb   t3, 0(t0)
    addi t0, t0, 1
    addi t1, t1, -1
    bnez t1, .L_clr_l
    ret

fb_flush:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s2, 8(sp)
    sw   s3, 4(sp)

    li   a0, 0x21; jal ssd1306_send_cmd
    li   a0, 28;   jal ssd1306_send_cmd
    li   a0, 99;   jal ssd1306_send_cmd

    li   a0, 0x22; jal ssd1306_send_cmd
    li   a0, 0x00; jal ssd1306_send_cmd
    li   a0, 0x04; jal ssd1306_send_cmd

    jal  i2c_start
    li   a0, 0x78
    jal  i2c_write_byte
    li   a0, 0x40
    jal  i2c_write_byte

    la   s2, framebuffer
    li   s3, 360
.L_flush_loop:
    beqz s3, .L_flush_done
    lbu  a0, 0(s2)
    jal  i2c_write_byte
    addi s2, s2, 1
    addi s3, s3, -1
    j    .L_flush_loop

.L_flush_done:
    jal  i2c_stop
    lw   s3, 4(sp)
    lw   s2, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret


# ---------------------------------------------------------
# SOFTWARE I2C (BIT-BANGING) ROUTINES
# ---------------------------------------------------------
i2c_delay:
    li   t5, 40
.L_i2c_d:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_i2c_d
    ret

sda_high:
    li   t0, 0x60004008; li t1, (1 << 5); sw t1, 0(t0); ret
sda_low:
    li   t0, 0x6000400C; li t1, (1 << 5); sw t1, 0(t0); ret
scl_high:
    li   t0, 0x60004008; li t1, (1 << 6); sw t1, 0(t0); ret
scl_low:
    li   t0, 0x6000400C; li t1, (1 << 6); sw t1, 0(t0); ret

i2c_start:
    addi sp, sp, -16; sw ra, 12(sp)
    jal sda_high; jal scl_high; jal i2c_delay
    jal sda_low; jal i2c_delay; jal scl_low; jal i2c_delay
    lw ra, 12(sp); addi sp, sp, 16; ret

i2c_stop:
    addi sp, sp, -16; sw ra, 12(sp)
    jal sda_low; jal scl_high; jal i2c_delay
    jal sda_high; jal i2c_delay
    lw ra, 12(sp); addi sp, sp, 16; ret

i2c_write_byte:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s2, 8(sp)
    mv   s2, a0
    li   t3, 8
.L_bit_loop:
    beqz t3, .L_write_ack
    andi t4, s2, 0x80
    bnez t4, .L_send_one
    jal  sda_low
    j    .L_clock_bit
.L_send_one:
    jal  sda_high
.L_clock_bit:
    jal  i2c_delay; jal scl_high; jal i2c_delay; jal scl_low; jal i2c_delay
    slli s2, s2, 1
    li   t6, 1
    sub  t3, t3, t6
    j    .L_bit_loop
.L_write_ack:
    jal  sda_high
    jal  i2c_delay; jal scl_high; jal i2c_delay; jal scl_low; jal i2c_delay
    lw   s2, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret


# ---------------------------------------------------------
# SSD1306 HIGH LEVEL HELPERS
# ---------------------------------------------------------
ssd1306_send_cmd:
    addi sp, sp, -16; sw ra, 12(sp); mv a2, a0
    jal i2c_start; li a0, 0x78; jal i2c_write_byte
    li a0, 0x80; jal i2c_write_byte; mv a0, a2; jal i2c_write_byte
    jal i2c_stop; lw ra, 12(sp); addi sp, sp, 16; ret


# ---------------------------------------------------------
# DATA & BSS SECTION
# ---------------------------------------------------------
    .align 4
ssd1306_init_cmds:
    .byte 0xAE    # Display OFF
    .byte 0xD5, 0x80
    .byte 0xA8, 0x27
    .byte 0xD3, 0x00
    .byte 0x40
    .byte 0x8D, 0x14
    .byte 0x20, 0x00
    .byte 0xA1
    .byte 0xC8
    .byte 0xDA, 0x12
    .byte 0x81, 0xCF
    .byte 0xD9, 0xF1
    .byte 0xDB, 0x40
    .byte 0xA4
    .byte 0xA6
    .byte 0xAF    # Display ON


# ---------------------------------------------------------
# VERTICAL TEXT SOURCE (Exact 40 rows for zero-copy scrolling)
# ---------------------------------------------------------
    .align 4
v_text_source:
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80

# Variables and Framebuffer in code section
    .align 4
v_scroll_pos:
    .word 0

    .align 4
framebuffer:
    .skip 360

_seg_end:
    .align 4
