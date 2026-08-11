# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly SSD1306 Text Scroller & LED
# Author:      agguro
# Date:        August 11, 2026
# Description: Pure assembly bare-metal driver to initialize SSD1306 OLED,
#              render a smooth pixel-based scrolling text engine from 
#              a virtual source buffer, flush via I2C (SDA=GPIO5, SCL=GPIO6), 
#              and control the LED on GPIO 8
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
    .byte 2                  # 0x02: SPI mode (2 = DIO)
    .byte 0                  # 0x03: SPI speed/size
    .word 0x40380000         # 0x04: Entry point address in IRAM
    .word 0                  # 0x08: WP pin / drive settings
    .half 5                  # 0x0C: Chip ID (ESP32-C3 = 5)
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
    # Block/disable all CPU interrupts during early boot setup
    csrci mstatus, 8

    # Set up the Stack Pointer (sp) to a safe RAM boundary
    li   sp, 0x3FCE0000
    li   t2, 0x7FFFBBFF      # Bitmask used to clear watchdog write-protect bits

    # =========================================================
    # BLOCK: WATCHDOG & DEBUG DISABLE INITIALIZATION
    # Disable all hardware watchdogs and JTAG/SWD interference
    # =========================================================

    # Disable Timer Group 0 (TG0) Watchdog
    li   t0, 0x6001F064
    li   t1, 0x50D83AA1
    sw   t1, 0(t0)
    li   t0, 0x6001F048
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable Timer Group 1 (TG1) Watchdog
    li   t0, 0x60020064
    sw   t1, 0(t0)
    li   t0, 0x60020048
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable RTC Watchdog
    li   t0, 0x600080A8
    sw   t1, 0(t0)
    li   t0, 0x60008090
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable Serial Wire Debug (SWD) / JTAG interference
    li   t0, 0x600080B8
    li   t1, 0x8F1D312A
    sw   t1, 0(t0)
    li   t0, 0x600080B4
    lw   t3, 0(t0)
    li   t4, 0x80000000
    or   t3, t3, t4
    sw   t3, 0(t0)

    # =========================================================
    # BLOCK: GPIO CONFIGURATION FOR I2C PINS & LED
    # Configure SDA (GPIO 5), SCL (GPIO 6), and LED (GPIO 8)
    # =========================================================
    li   t0, 0x60009018      # IO_MUX_GPIO5_REG (SDA)
    li   t1, (1 << 12) | (1 << 8)
    sw   t1, 0(t0)
    li   t0, 0x6000901C      # IO_MUX_GPIO6_REG (SCL)
    sw   t1, 0(t0)

    li   t0, 0x60004088      # GPIO_PIN5_REG (Pull-up / Open-drain configuration)
    li   t1, (1 << 2)
    sw   t1, 0(t0)
    li   t0, 0x6000408C      # GPIO_PIN6_REG
    sw   t1, 0(t0)

    li   t0, 0x60004020      # GPIO_ENABLE_REG
    li   t1, (1 << 5) | (1 << 6) | (1 << 8)
    sw   t1, 0(t0)

    li   s0, 0x60004008      # W1TS (Set High)
    li   s1, 0x6000400C      # W1TC (Set Low / Clear)
    li   t1, (1 << 5) | (1 << 6)
    sw   t1, 0(s0)

    # Boot stabilization delay for display power-up
    li   t5, 500000
.L_boot_delay:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_boot_delay


    # =========================================================
    # BLOCK: SSD1306 OLED INITIALIZATION SEQUENCE
    # Iterate through command table and send setup bytes over I2C
    # =========================================================
.L_init_display:
    la   s4, ssd1306_init_cmds
    li   s5, 25

.L_init_loop:
    beqz s5, .L_start_scroller
    lbu  a0, 0(s4)
    jal  ssd1306_send_cmd
    addi s4, s4, 1
    addi s5, s5, -1
    j    .L_init_loop


# =========================================================
# BLOCK: SCROLLER MAIN APPLICATION
# Continuously shift scroll offset, render frame, and flush
# =========================================================
.L_start_scroller:
    li   s6, 0               # s6 = scroll offset (start at pixel 0)

scroll_loop:
    # Turn LED ON (active low on this board, so W1TC = 400C)
    li   t1, 0x100
    sw   t1, 0(s1)

    # Render running text into framebuffer based on scroll offset s6
    mv   a0, s6
    jal  render_scroller_frame

    # Send framebuffer to OLED display
    jal  fb_flush

    # Turn LED OFF
    sw   t1, 0(s0)

    # Increment scroll offset for next frame (shift 1 pixel left)
    addi s6, s6, 1
    li   t0, 72              # Total width of our scroll buffer is exactly 72 columns
    bne  s6, t0, .L_skip_reset
    li   s6, 0               # Wrap around when reaching the end
.L_skip_reset:

    # Animation delay (scroller speed control)
    li   t5, 30000
.L_scroll_d:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_scroll_d

    j    scroll_loop


# =========================================================
# ROUTINE: RENDER SCROLLER FRAME
# Pixel-based shifting routine: a0 = scroll_offset (s6)
# =========================================================
render_scroller_frame:
    addi sp, sp, -32
    sw   ra, 28(sp)
    sw   s2, 24(sp)
    sw   s3, 20(sp)
    sw   s4, 16(sp)
    sw   s5, 12(sp)
    mv   s2, a0              # s2 = scroll offset

    # Fill all 5 pages of the screen (Page 0 to 4)
    li   s3, 0               # s3 = current page (0 to 4)

.L_page_blit_loop:
    # Calculate RAM target address for this page in framebuffer
    la   t0, framebuffer
    li   t1, 72
    mul  t2, s3, t1
    add  s4, t0, t2          # s4 = pointer to start of this page in framebuffer

    # Loop over all 72 columns of the screen
    li   s5, 0               # s5 = column counter (0 to 71)

.L_col_blit_loop:
    # Calculate column index to fetch from scroll_source table:
    # index = (column + scroll_offset) % 72
    add  t3, s5, s2          # column + offset
    li   t4, 72
    remu t3, t3, t4          # modulo 72 (wrap around)

    # Fetch correct byte from scroll_source table based on page (s3) and computed column (t3)
    la   t5, scroll_source
    li   t1, 72
    mul  t6, s3, t1          # page offset in scroll_source
    add  t5, t5, t6
    add  t5, t5, t3          # definitive byte address
    lbu  t0, 0(t5)           # load byte

    # Store byte into active framebuffer
    sb   t0, 0(s4)

    # Next column
    addi s4, s4, 1
    addi s5, s5, 1
    li   t1, 72
    bne  s5, t1, .L_col_blit_loop

    # Next page
    addi s3, s3, 1
    li   t1, 5
    bne  s3, t1, .L_page_blit_loop

    lw   s5, 12(sp)
    lw   s4, 16(sp)
    lw   s3, 20(sp)
    lw   s2, 24(sp)
    lw   ra, 28(sp)
    addi sp, sp, 32
    ret


# =========================================================
# BLOCK: FRAMEBUFFER ROUTINES
# Flush framebuffer RAM contents via I2C to display RAM
# =========================================================
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


# =========================================================
# BLOCK: SOFTWARE I2C (BIT-BANGING) ROUTINES
# Low-level protocol control for custom SDA/SCL signal timing
# =========================================================
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


# =========================================================
# BLOCK: SSD1306 HIGH-LEVEL HELPERS
# Protocol wrappers for sending commands and data streams
# =========================================================
ssd1306_send_cmd:
    addi sp, sp, -16; sw ra, 12(sp); mv a2, a0
    jal i2c_start; li a0, 0x78; jal i2c_write_byte
    li a0, 0x80; jal i2c_write_byte; mv a0, a2; jal i2c_write_byte
    jal i2c_stop; lw ra, 12(sp); addi sp, sp, 16; ret


# =========================================================
# BLOCK: DATA & BSS SECTION
# Constants, initialization arrays, and scroll source font data
# =========================================================
    .align 4
ssd1306_init_cmds:
    .byte 0xAE       # Display OFF
    .byte 0xD5, 0x80 # Set display clock divide ratio/oscillator frequency
    .byte 0xA8, 0x27 # Set multiplex ratio (40 rows)
    .byte 0xD3, 0x00 # Set display offset
    .byte 0x40       # Set start line address
    .byte 0x8D, 0x14 # Charge pump setting (Enable charge pump during display on)
    .byte 0x20, 0x00 # Set memory addressing mode (0x00 = horizontal mode)
    .byte 0xA1       # Set segment re-map (column address 0 mapped to seg 127)
    .byte 0xC8       # Set COM output scan direction
    .byte 0xDA, 0x12 # Set COM pins hardware configuration
    .byte 0x81, 0xCF # Set contrast control register
    .byte 0xD9, 0xF1 # Set pre-charge period
    .byte 0xDB, 0x40 # Set VCOMH deselect level
    .byte 0xA4       # Entire display on (resume to RAM content)
    .byte 0xA6       # Set normal display (not inverted)
    .byte 0xAF       # Display ON

# Virtual scroll source buffer (exactly 72 columns wide per page = 360 bytes total)
.align 4
scroll_source:
    # --- PAGE 0 ---
    .rept 72
    .byte 0x00
    .endr

    # --- PAGE 1 ("SCROLLING") ---
    .byte 0x00, 0x46, 0x49, 0x49, 0x31, 0x00               # S
    .byte 0x00, 0x3E, 0x41, 0x41, 0x22, 0x00               # C
    .byte 0x00, 0x7F, 0x09, 0x19, 0x66, 0x00               # R
    .byte 0x00, 0x3E, 0x41, 0x41, 0x3E, 0x00               # O
    .byte 0x00, 0x7F, 0x40, 0x40, 0x40, 0x00               # L
    .byte 0x00, 0x7F, 0x40, 0x40, 0x40, 0x00               # L
    .byte 0x00, 0x41, 0x7F, 0x41, 0x00                     # I
    .byte 0x00, 0x7F, 0x02, 0x04, 0x7F, 0x00               # N
    .byte 0x00, 0x3E, 0x41, 0x49, 0x3A, 0x00               # G
    # Fill remaining space up to exactly 72 columns with 0x00 (72 - 53 = 19 bytes)
    .rept 19
    .byte 0x00
    .endr

    # --- PAGE 2 ---
    .rept 72
    .byte 0x00
    .endr

    # --- PAGE 3 ---
    .rept 72
    .byte 0x00
    .endr

    # --- PAGE 4 ---
    .rept 72
    .byte 0x00
    .endr


# Reserve active Framebuffer in RAM (360 bytes)
    .section .bss
    .align 4
framebuffer:
    .skip 360

_seg_end:
    .align 4
