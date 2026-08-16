# =====================================================================
# Project:     Bare-Metal ESP32-C3 Host Loader (Native USB-JTAG)
# Name:        esp32c3_host.s
# Author:      agguro
# Date:        August 14, 2026
# Description: x86_64 host tool with fully embedded fallback binary
#              bytes directly inside the code section, featuring
#              dynamic command-line parsing for both port (-p) and kernel path.
#
# Copyright 2026 agguro
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# =====================================================================

.global _start

# =====================================================================
# BSS Section - Uninitialized Global Variables and Buffers
# =====================================================================
.section .bss
    .lcomm fd, 8                  # File descriptor for serial device connection
    .lcomm read_buf, 256          # Input buffer for reading responses from the chip
    .lcomm termios, 60            # Terminal attributes structure for serial configuration
    .lcomm payload_buf, 4096      # Memory buffer to hold loaded kernel or fallback binary
    .lcomm kernel_size, 8         # Size variable storage allocation (8 bytes)
    .lcomm dev_path_ptr, 8        # Pointer to active device path string
    .lcomm kernel_path_ptr, 8     # Pointer to active kernel binary path string

# =====================================================================
# Read-Only Data Section - Strings, Protocol Packets, and Embedded Binary
# =====================================================================
.section .rodata
    default_kernel: .string "esp32c3_kernel.bin"
    default_dev:    .string "/dev/ttyACM0"
    
    msg_open_err:   .string "Error: Could not open port "
    len_open_err  = . - msg_open_err
    
    msg_open_ok:    .string "[HOST] Port opened & Native USB-JTAG reset executed.\n"
    len_open_ok   = . - msg_open_ok - 1

    msg_fallback:   .string "[HOST] WARNING: Kernel file not found! Using embedded fallback kernel.\n"
    len_fallback  = . - msg_fallback - 1

    msg_upload:     .string "[HOST] Uploading SLIP-escaped RISC-V kernel...\n"
    len_upload    = . - msg_upload - 1

    msg_running:    .string "[HOST] Kernel execution started! Listening for output (Ctrl+C to exit)...\n"
    len_running   = . - msg_running - 1

    msg_close:      .string "\n[HOST] Port successfully closed. Program exits.\n"
    len_close     = . - msg_close - 1

    msg_sync_err:   .string "[HOST] ERROR: Synchronization with ESP32-C3 failed after 50 attempts.\n"
    len_sync_err  = . - msg_sync_err - 1
    
    newline_str:    .string "\n"
    len_newline   = 1

    # Nanosleep timestamps for precise delay intervals
    sleep_100ms_ts: .quad 0, 100000000
    sleep_200ms_ts: .quad 0, 200000000

    # ESP32-C3 Serial Protocol: Synchronization Handshake Packet
    sync_packet:
        .byte 0xC0                    
        .byte 0x00, 0x08              # Command: ESP_SYNC
        .2byte 36                     # Data length descriptor
        .4byte 0                      # Checksum placeholder
        .byte 0x07, 0x07, 0x12, 0x20  # Sync sync bytes
        .fill 32, 1, 0x55             # Training payload bytes
        .byte 0xC0                    
    sync_len = . - sync_packet

    # ESP32-C3 Serial Protocol: Attach SPI Flash/Peripheral Interface Packet
    attach_packet:
        .byte 0xC0                    
        .byte 0x00, 0x0B              # Command: ESP_SPI_ATTACH
        .2byte 8                      # Data length descriptor
        .4byte 0                      # Checksum placeholder
        .4byte 0, 0                   # Arguments descriptor
        .byte 0xC0                    
    attach_len = . - attach_packet

    # ESP32-C3 Protocol: Execution Vector Trigger Packet (MEM_END)
    run_packet:
        .byte 0xC0                    
        .byte 0x00, 0x06              # Command: ESP_MEM_END
        .2byte 8                      # Data length descriptor
        .4byte 0                      # Checksum placeholder
        .4byte 0                      # Execution flag (0 = execute target entry)
        .4byte 0x40380000             # Entry point address in SRAM
        .byte 0xC0                    
    run_len = . - run_packet

    # Embedded Fallback Binary: Fully compiled RISC-V blink & heartbeat routine
    fallback_bin:
        # --- CPU & Environment Initialization ---
        .byte 0x73, 0x70, 0x04, 0x30    # csrci mstatus, 8 (Disable global interrupts)
        .byte 0x37, 0x01, 0xce, 0x3f    # lui sp, 0x3fce0 (Initialize Stack Pointer base)
        .byte 0xb7, 0xc3, 0xff, 0x7f    # lui t2, 0x7fffc (Load watchdog clear mask upper)
        .byte 0x93, 0x83, 0xf3, 0xbf    # addi t2, t2, -1025 (Complete watchdog clear mask)
        
        # --- Watchdog Timer (WDT) & Debug Disable Sequence ---
        .byte 0xb7, 0xf2, 0x01, 0x60    # lui t0, 0x6001f (Timer Group 0 WDT config base)
        .byte 0x93, 0x82, 0x42, 0x06    # addi t0, t0, 100 (Offset to WDT WPROTECT register)
        .byte 0x37, 0x43, 0xd8, 0x50    # lui t1, 0x50d84 (WDT write protection disable key upper)
        .byte 0x13, 0x03, 0x13, 0xaa    # addi t1, t1, -1375 (WDT write protection disable key lower)
        .byte 0x23, 0xa0, 0x62, 0x00    # sw t1, 0(t0) (Unlock TG0 WDT write protection)
        .byte 0xb7, 0xf2, 0x01, 0x60    # lui t0, 0x6001f (Timer Group 0 base)
        .byte 0x93, 0x82, 0x82, 0x04    # addi t0, t0, 72 (Offset to TG0 WDT CONFIG register)
        .byte 0x03, 0xae, 0x02, 0x00    # lw t3, 0(t0) (Load TG0 WDT config value)
        .byte 0x33, 0x7e, 0x7e, 0x00    # and t3, t3, t2 (Mask out WDT enable bits)
        .byte 0x23, 0xa0, 0xc2, 0x01    # sw t3, 0(t0) (Disable TG0 Watchdog Timer)
        .byte 0xb7, 0x02, 0x02, 0x60    # lui t0, 0x60020 (Timer Group 1 WDT config base)
        .byte 0x93, 0x82, 0x42, 0x06    # addi t0, t0, 100 (Offset to TG1 WDT WPROTECT register)
        .byte 0x23, 0xa0, 0x62, 0x00    # sw t1, 0(t0) (Unlock TG1 WDT write protection)
        .byte 0xb7, 0x02, 0x02, 0x60    # lui t0, 0x60020 (Timer Group 1 base)
        .byte 0x93, 0x82, 0x82, 0x04    # addi t0, t0, 72 (Offset to TG1 WDT CONFIG register)
        .byte 0x03, 0xae, 0x02, 0x00    # lw t3, 0(t0) (Load TG1 WDT config value)
        .byte 0x33, 0x7e, 0x7e, 0x00    # and t3, t3, t2 (Mask out WDT enable bits)
        .byte 0x23, 0xa0, 0xc2, 0x01    # sw t3, 0(t0) (Disable TG1 Watchdog Timer)
        .byte 0xb7, 0x82, 0x00, 0x60    # lui t0, 0x60008 (RTC Super Watchdog base)
        .byte 0x93, 0x82, 0x82, 0x0a    # addi t0, t0, 168 (Offset to RTC WDT WPROTECT register)
        .byte 0x23, 0xa0, 0x62, 0x00    # sw t1, 0(t0) (Unlock RTC WDT write protection)
        .byte 0xb7, 0x82, 0x00, 0x60    # lui t0, 0x60008 (RTC base)
        .byte 0x93, 0x82, 0x02, 0x09    # addi t0, t0, 144 (Offset to RTC WDT CONFIG register)
        .byte 0x03, 0xae, 0x02, 0x00    # lw t3, 0(t0) (Load RTC WDT config value)
        .byte 0x33, 0x7e, 0x7e, 0x00    # and t3, t3, t2 (Mask out RTC WDT enable bits)
        .byte 0x23, 0xa0, 0xc2, 0x01    # sw t3, 0(t0) (Disable RTC Watchdog Timer)
        .byte 0xb7, 0x82, 0x00, 0x60    # lui t0, 0x60008 (RTC base)
        .byte 0x93, 0x82, 0x82, 0x0b    # addi t0, t0, 184 (Offset to JTAG protection register)
        .byte 0x37, 0x33, 0x1d, 0x8f    # lui t1, 0x8f1d3 (JTAG disable key upper)
        .byte 0x13, 0x03, 0xa3, 0x12    # addi t1, t1, 298 (JTAG disable key lower)
        .byte 0x23, 0xa0, 0x62, 0x00    # sw t1, 0(t0) (Unlock JTAG control register)
        .byte 0xb7, 0x82, 0x00, 0x60    # lui t0, 0x60008 (RTC base)
        .byte 0x93, 0x82, 0x42, 0x0b    # addi t0, t0, 180 (Offset to SWD/JTAG conf register)
        .byte 0x03, 0xae, 0x02, 0x00    # lw t3, 0(t0) (Load current JTAG conf)
        .byte 0xb7, 0x0e, 0x00, 0x80    # lui t4, 0x80000 (Disable debug bit mask)
        .byte 0x33, 0x6e, 0xde, 0x01    # or t3, t3, t4 (Apply debug disable bit)
        .byte 0x23, 0xa0, 0xc2, 0x01    # sw t3, 0(t0) (Store updated JTAG configuration)
        
        # --- GPIO Configuration for LED Pin (GPIO 8) ---
        .byte 0xb7, 0x92, 0x00, 0x60    # lui t0, 0x60009 (IO_MUX base address)
        .byte 0x93, 0x82, 0x42, 0x02    # addi t0, t0, 36 (Offset to IO_MUX_GPIO8_REG)
        .byte 0x05, 0x63                # lui t1, 0x1 (Select standard GPIO function - compressed)
        .byte 0x23, 0xa0, 0x62, 0x00    # sw t1, 0(t0) (Apply IO_MUX setting for GPIO 8)
        .byte 0xb7, 0x42, 0x00, 0x60    # lui t0, 0x60004 (GPIO peripheral base address)
        .byte 0x93, 0x82, 0x42, 0x02    # addi t0, t0, 36 (Offset to GPIO_ENABLE_W1TS_REG)
        .byte 0x13, 0x03, 0x00, 0x10    # li t1, 256 (Bit mask for GPIO 8 -> 1 << 8)
        .byte 0x23, 0xa0, 0x62, 0x00    # sw t1, 0(t0) (Enable GPIO 8 as digital output)
        .byte 0xb7, 0x42, 0x00, 0x60    # lui t0, 0x60004 (GPIO peripheral base address)
        .byte 0xa1, 0x02                # addi t0, t0, 8 (Offset to GPIO_OUT_W1TS_REG - compressed)
        .byte 0x13, 0x03, 0x00, 0x10    # li t1, 256 (Pin mask for GPIO 8)
        
        # --- Infinite Blink Loop with Delay ---
        .byte 0x23, 0xa0, 0x62, 0x00    # sw t1, 0(t0) (Write to current target register address in t0)
        .byte 0xb7, 0xA3, 0x07, 0x00    # lui t2, ... (Load high bits for loop delay counter)
        .byte 0x93, 0x83, 0x03, 0x12    # addi t2, t2, ... (Load low bits for loop delay counter)
        .byte 0xfd, 0x13                # addi t2, t2, -1 (Decrement counter - compressed)
        .byte 0xe3, 0x9f, 0x03, 0xfe    # bnez t2, delay_loop (Branch back if counter not zero)
        .byte 0x93, 0xc2, 0x42, 0x00    # xori t0, t0, 4 (Toggle t0 between W1TS and W1TC register offsets)
        .byte 0xed, 0xb7                # j blink_loop (Jump back to start of blink loop - compressed)
    fallback_bin_end:

# =====================================================================
# Data Section - SLIP Framing Constants and Protocol Command Templates
# =====================================================================
.section .data
    slip_boundary:    .byte 0xC0    # SLIP packet delimiter byte
    slip_esc:         .byte 0xDB    # SLIP escape character
    slip_esc_c0:      .byte 0xDC    # Escaped mapping for 0xC0
    slip_esc_db:      .byte 0xDD    # Escaped mapping for 0xDB

    # ESP32-C3 Protocol Command: Initialize SRAM Allocation Block (MEM_BEGIN)
    mem_begin_packet:
        .byte 0xC0                    
        .byte 0x00, 0x05              # Command: ESP_MEM_BEGIN
        .2byte 16                     # Payload length (16 bytes)
        .4byte 0                      # Checksum placeholder
        .4byte 0                      # Dynamically filled payload size
        .4byte 1                      # Number of packet blocks
        .4byte 0x400                  # Block size
        .4byte 0x40380000             # Target destination address in SRAM
        .byte 0xC0                    
    mem_begin_len = . - mem_begin_packet

    # ESP32-C3 Protocol Command Template: Stream Data Chunk (MEM_DATA)
    mem_data_cmd: 
        .byte 0x00, 0x07              # Command: ESP_MEM_DATA
        .2byte 0                      # Length placeholder
        .4byte 0                      # Checksum placeholder
        .4byte 0                      # Sequence number
        .4byte 0                      # Reserved padding
        .4byte 0, 0                   

# =====================================================================
# Text Section - Host Entry Point and Main Control Flow
# =====================================================================
.section .text
_start:
    # -----------------------------------------------------------------
    # Step -1: Parse Command Line Arguments (argc, argv)
    # Supported forms:
    #   1. esp32c3_host
    #   2. esp32c3_host kernel.bin
    #   3. esp32c3_host -p /dev/ttyACM1
    #   4. esp32c3_host -p /dev/ttyACM1 kernel.bin
    #   5. esp32c3_host kernel.bin -p /dev/ttyACM1
    # -----------------------------------------------------------------
    movq (%rsp), %r8              # Load argc into %r8
    leaq 8(%rsp), %r9             # Load argv array pointer into %r9 (%r9 points to argv[0])

    # Set default values initially
    leaq default_dev(%rip), %rax
    movq %rax, dev_path_ptr(%rip)
    leaq default_kernel(%rip), %rax
    movq %rax, kernel_path_ptr(%rip)

    cmpq $2, %r8                  # Check if argc < 2 (no arguments)
    jl check_kernel_file          # If so, proceed with defaults

    # Setup pointer index to argv[1]
    movq 8(%r9), %rsi             # %rsi = argv[1]
    
    # Check if argv[1] is "-p"
    movw (%rsi), %ax              # Load first 2 characters of argv[1]
    cmpw $0x702d, %ax             # Check if it equals "-p" (ASCII '-' = 0x2D, 'p' = 0x70)
    je parse_p_flag_first

    # If argv[1] is not "-p", treat it as the kernel path
    movq %rsi, kernel_path_ptr(%rip)

    # Check if there is a third argument (argv[2], which could be "-p")
    cmpq $3, %r8
    jl check_kernel_file
    movq 16(%r9), %rsi            # %rsi = argv[2]
    movw (%rsi), %ax
    cmpw $0x702d, %ax             # Check if argv[2] is "-p"
    jne check_kernel_file
    
    # If argv[2] is "-p", then argv[3] must be the port path
    cmpq $4, %r8
    jl check_kernel_file
    movq 24(%r9), %rsi            # %rsi = argv[3] (port path)
    movq %rsi, dev_path_ptr(%rip)
    jmp check_kernel_file

parse_p_flag_first:
    # argv[1] was "-p", so argv[2] must be the port path
    cmpq $3, %r8
    jl check_kernel_file
    movq 16(%r9), %rsi            # %rsi = argv[2] (port path)
    movq %rsi, dev_path_ptr(%rip)

    # Check if there is a fourth argument (argv[3], which would be the kernel path)
    cmpq $4, %r8
    jl check_kernel_file
    movq 24(%r9), %rsi            # %rsi = argv[3] (kernel path)
    movq %rsi, kernel_path_ptr(%rip)

# -----------------------------------------------------------------
# Step 0: Open and Read Kernel Binary File from Disk
# -----------------------------------------------------------------
check_kernel_file:
    movq $2, %rax                 # Syscall number 2: sys_open
    movq kernel_path_ptr(%rip), %rdi # Pointer to dynamic kernel filename string
    movq $0, %rsi                 # Flags: O_RDONLY (Read-only mode)
    movq $0, %rdx                 # Mode: 0
    syscall                       # Execute system call
    
    cmpq $0, %rax                 # Check if file descriptor is valid (>= 0)
    js load_fallback_kernel       # If negative (error/not found), jump to fallback routine
    
    # Read custom kernel binary file into memory payload buffer
    movq %rax, %r8                # Save file descriptor in register %r8
    movq $0, %rax                 # Syscall number 0: sys_read
    movq %r8, %rdi                # File descriptor argument
    leaq payload_buf(%rip), %rsi  # Destination memory buffer pointer
    movq $4096, %rdx              # Maximum buffer read size (4KB)
    syscall                       # Execute system call
    movq %rax, %r9                # Save exact number of bytes read
    
    # Close custom kernel file descriptor
    movq $3, %rax                 # Syscall number 3: sys_close
    movq %r8, %rdi                # File descriptor argument
    syscall
    
    movq %r9, kernel_size(%rip)   # Store actual kernel size variable
    jmp start_host_sequence       # Proceed to serial communication flow

# ---------------------------------------------------------------------
# Fallback Routine: Load embedded fallback binary if kernel file is missing
# ---------------------------------------------------------------------
load_fallback_kernel:
    movq $1, %rax                 # Syscall number 1: sys_write
    movq $1, %rdi                 # File descriptor 1: stdout
    leaq msg_fallback(%rip), %rsi # Pointer to warning message string
    movq $len_fallback, %rdx      # Length of warning message
    syscall
    
    leaq fallback_bin(%rip), %rsi # Source pointer of embedded fallback binary
    leaq fallback_bin_end(%rip), %rcx # End pointer of fallback binary
    subq %rsi, %rcx               # Calculate exact size of fallback binary
    movq %rcx, kernel_size(%rip)  # Store size in kernel_size variable
    
    leaq payload_buf(%rip), %rdi  # Destination pointer in payload buffer
    rep movsb                     # Copy bytes from source to destination buffer

# ---------------------------------------------------------------------
# Step 1: Open Serial Communication Port (Dynamic Device Path)
# ---------------------------------------------------------------------
start_host_sequence:
    movq $2, %rax                 # Syscall number 2: sys_open
    movq dev_path_ptr(%rip), %rdi # Load active device path string pointer
    movq $2, %rsi                 # Flags: O_RDWR (Read/Write access)
    movq $0, %rdx                 # Mode: 0
    syscall                       # Open serial port file descriptor
    cmpq $0, %rax                 # Check if file descriptor is valid
    js open_failed                # Jump to error handler if open failed
    movq %rax, fd(%rip)           # Save serial port file descriptor

    # -----------------------------------------------------------------
    # Step 1.1: Hardware Reset Sequence via Native USB-JTAG Control Lines
    # -----------------------------------------------------------------
    subq $8, %rsp                 # Allocate temporary stack space for ioctl arguments
    
    # Assert DTR and clear RTS
    movl $0x006, (%rsp)
    movq $16, %rax                # Syscall number 16: sys_ioctl
    movq fd(%rip), %rdi           # Serial port file descriptor
    movq $0x5417, %rsi            # Request: TIOCMBIS (Set modem bits)
    movq %rsp, %rdx               # Pointer to argument value
    syscall
    call do_sleep_100ms           # Hold state briefly
    
    # Clear DTR
    movl $0x002, (%rsp)
    movq $16, %rax                # Syscall number 16: sys_ioctl
    movq fd(%rip), %rdi           # Serial port file descriptor
    movq $0x5416, %rsi            # Request: TIOCMBIC (Clear modem bits)
    movq %rsp, %rdx               # Pointer to argument value
    syscall
    
    # Assert RTS
    movl $0x004, (%rsp)
    movq $16, %rax                # Syscall number 16: sys_ioctl
    movq fd(%rip), %rdi           # Serial port file descriptor
    movq $0x5417, %rsi            # Request: TIOCMBIS (Set modem bits)
    movq %rsp, %rdx               # Pointer to argument value
    syscall
    call do_sleep_100ms           # Hold state briefly
    
    # Clear RTS
    movl $0x004, (%rsp)
    movq $16, %rax                # Syscall number 16: sys_ioctl
    movq fd(%rip), %rdi           # Serial port file descriptor
    movq $0x5416, %rsi            # Request: TIOCMBIC (Clear modem bits)
    movq %rsp, %rdx               # Pointer to argument value
    syscall
    
    # Assert DTR
    movl $0x002, (%rsp)
    movq $16, %rax                # Syscall number 16: sys_ioctl
    movq fd(%rip), %rdi           # Serial port file descriptor
    movq $0x5417, %rsi            # Request: TIOCMBIS (Set modem bits)
    movq %rsp, %rdx               # Pointer to argument value
    syscall
    
    # Assert RTS (Finalize bootstrap enter sequence)
    movl $0x004, (%rsp)
    movq $16, %rax                # Syscall number 16: sys_ioctl
    movq fd(%rip), %rdi           # Serial port file descriptor
    movq $0x5417, %rsi            # Request: TIOCMBIS (Set modem bits)
    movq %rsp, %rdx               # Pointer to argument value
    syscall
    
    addq $8, %rsp                 # Restore stack pointer
    call do_sleep_200ms           # Allow chip hardware bootloader to stabilize

    # -----------------------------------------------------------------
    # Step 1.2: Configure Serial Port Terminal Attributes (Raw Mode)
    # -----------------------------------------------------------------
    movq $16, %rax                # Syscall number 16: sys_ioctl
    movq fd(%rip), %rdi           # Serial port file descriptor
    movq $0x5401, %rsi            # Request: TCGETS (Get terminal attributes)
    leaq termios(%rip), %rdx      # Pointer to termios struct buffer
    syscall
    
    # Modify termios flags to establish raw binary communication mode
    movl $0, termios+0(%rip)      # Clear input flags (c_iflag)
    movl $0, termios+4(%rip)      # Clear output flags (c_oflag)
    movl $0, termios+12(%rip)     # Clear local flags (c_lflag)
    movl $0x000018B2, termios+8(%rip) # Set control flags (c_cflag: B115200, CS8, CREAD, CLOCAL)
    movb $2, termios+22(%rip)     # Set VMIN = 2
    movb $0, termios+23(%rip)     # Set VTIME = 0
    
    movq $16, %rax                # Syscall number 16: sys_ioctl
    movq fd(%rip), %rdi           # Serial port file descriptor
    movq $0x5402, %rsi            # Request: TCSETS (Set terminal attributes)
    leaq termios(%rip), %rdx      # Pointer to termios struct buffer
    syscall

# ---------------------------------------------------------------------
# Step 1.3: Drain any stale log data remaining in the serial input buffer
# ---------------------------------------------------------------------
drain_logs:
    movq $0, %rax                 # Syscall number 0: sys_read
    movq fd(%rip), %rdi           # Serial port file descriptor
    leaq read_buf(%rip), %rsi     # Input read buffer pointer
    movq $256, %rdx               # Read chunk size (256 bytes)
    syscall
    cmpq $0, %rax                 # Check if bytes were read (> 0)
    jg drain_logs                 # Loop until input buffer is completely drained

    # Print success message indicating port is open and reset executed
    movq $1, %rax                 # Syscall number 1: sys_write
    movq $1, %rdi                 # File descriptor 1: stdout
    leaq msg_open_ok(%rip), %rsi  # Pointer to success message string
    movq $len_open_ok, %rdx       # Length of success message
    syscall

    # -----------------------------------------------------------------
    # Step 2: Establish Protocol Synchronization Loop with Bootloader
    # -----------------------------------------------------------------
    movq $50, %r13                # Set maximum retry attempts counter to 50
send_sync_loop:
    decq %r13                     # Decrement retry counter
    js sync_failed                # If counter reaches zero, jump to synchronization error handler
    
    leaq sync_packet(%rip), %rsi  # Pointer to sync packet bytes
    movq $sync_len, %rdx          # Length of sync packet
    call send_packet_safe         # Send sync command packet over serial port
    
    movq $0, %rax                 # Syscall number 0: sys_read
    movq fd(%rip), %rdi           # Serial port file descriptor
    leaq read_buf(%rip), %rsi     # Response read buffer pointer
    movq $64, %rdx                # Read buffer size (64 bytes)
    syscall
    cmpq $0, %rax                 # Check if response data was received
    jle send_sync_loop            # If no data or error, retry synchronization packet
    
    movzbq read_buf+2(%rip), %rax # Extract response command status byte
    cmpq $0x08, %rax              # Check if response matches expected sync ACK (0x08)
    jne send_sync_loop            # If acknowledgment does not match, retry loop
    
    # -----------------------------------------------------------------
    # Step 3: Issue SPI Peripheral Attachment Command Sequence
    # -----------------------------------------------------------------
    leaq attach_packet(%rip), %rsi# Pointer to attach packet bytes
    movq $attach_len, %rdx        # Length of attach packet
    call send_packet_safe         # Send SPI attach packet over serial port
    
read_attach_retry:
    movq $0, %rax                 # Syscall number 0: sys_read
    movq fd(%rip), %rdi           # Serial port file descriptor
    leaq read_buf(%rip), %rsi     # Response read buffer pointer
    movq $32, %rdx                # Read buffer size (32 bytes)
    syscall
    cmpq $0, %rax                 # Check if response was received
    jle read_attach_retry         # Retry reading until response arrives

    # Print upload notification message to terminal
    movq $1, %rax                 # Syscall number 1: sys_write
    movq $1, %rdi                 # File descriptor 1: stdout
    leaq msg_upload(%rip), %rsi   # Pointer to upload message string
    movq $len_upload, %rdx        # Length of upload message
    syscall

    # -----------------------------------------------------------------
    # Step 4: Initialize SRAM Memory Block Allocation (MEM_BEGIN)
    # -----------------------------------------------------------------
    movq kernel_size(%rip), %rax  # Load exact kernel binary size
    movl %eax, mem_begin_packet+12(%rip) # Insert dynamic size into MEM_BEGIN packet header

    leaq mem_begin_packet(%rip), %rsi # Pointer to MEM_BEGIN packet bytes
    movq $mem_begin_len, %rdx     # Length of MEM_BEGIN packet
    call send_packet_safe         # Send allocation command packet over serial port
    
read_mem_begin_retry:
    movq $0, %rax                 # Syscall number 0: sys_read
    movq fd(%rip), %rdi           # Serial port file descriptor
    leaq read_buf(%rip), %rsi     # Response read buffer pointer
    movq $32, %rdx                # Read buffer size (32 bytes)
    syscall
    cmpq $0, %rax                 # Check if response was received
    jle read_mem_begin_retry      # Retry reading acknowledgment

    # -----------------------------------------------------------------
    # Step 5: Stream Kernel Payload Bytes via SLIP-Escaped MEM_DATA Packets
    # -----------------------------------------------------------------
    call process_and_send_mem_data# Process checksum and stream payload bytes with SLIP framing
    
read_mem_data_retry:
    movq $0, %rax                 # Syscall number 0: sys_read
    movq fd(%rip), %rdi           # Serial port file descriptor
    leaq read_buf(%rip), %rsi     # Response read buffer pointer
    movq $32, %rdx                # Read buffer size (32 bytes)
    syscall
    cmpq $0, %rax                 # Check if response was received
    jle read_mem_data_retry       # Retry reading data transfer acknowledgment

    # -----------------------------------------------------------------
    # Step 6: Trigger Kernel Execution Vector (MEM_END / Run Command)
    # -----------------------------------------------------------------
    leaq run_packet(%rip), %rsi   # Pointer to run packet bytes
    movq $run_len, %rdx           # Length of run packet
    call send_packet_safe         # Send execution trigger command packet
    call do_sleep_100ms           # Brief pause for execution handoff

# ---------------------------------------------------------------------
# Step 7: Drain Final Bootloader Acknowledgments and Restore Terminal Mode
# ---------------------------------------------------------------------
drain_final_ack:
    movq $0, %rax                 # Syscall number 0: sys_read
    movq fd(%rip), %rdi           # Serial port file descriptor
    leaq read_buf(%rip), %rsi     # Read buffer pointer
    movq $64, %rdx                # Read chunk size (64 bytes)
    syscall
    cmpq $0, %rax                 # Check if trailing bytes remain in buffer
    jg drain_final_ack            # Loop until input buffer is fully cleared

    # Restore normal terminal attribute settings (Canonical mode)
    movq $16, %rax                # Syscall number 16: sys_ioctl
    movq fd(%rip), %rdi           # Serial port file descriptor
    movq $0x5401, %rsi            # Request: TCGETS
    leaq termios(%rip), %rdx      # Pointer to termios struct buffer
    syscall
    
    movb $0, termios+22(%rip)     # Clear VMIN = 0
    movb $1, termios+23(%rip)     # Set VTIME = 1
    
    movq $16, %rax                # Syscall number 16: sys_ioctl
    movq fd(%rip), %rdi           # Serial port file descriptor
    movq $0x5402, %rsi            # Request: TCSETS
    leaq termios(%rip), %rdx      # Pointer to termios struct buffer
    syscall

    # Print kernel execution started message
    movq $1, %rax                 # Syscall number 1: sys_write
    movq $1, %rdi                 # File descriptor 1: stdout
    leaq msg_running(%rip), %rsi  # Pointer to running message string
    movq $len_running, %rdx       # Length of running message
    syscall

# ---------------------------------------------------------------------
# Step 8: Interactive Terminal Listener Loop (Echo output from chip)
# ---------------------------------------------------------------------
listen_kernel:
    movq $0, %rax                 # Syscall number 0: sys_read
    movq fd(%rip), %rdi           # Serial port file descriptor
    leaq read_buf(%rip), %rsi     # Input read buffer pointer
    movq $256, %rdx               # Read chunk size (256 bytes)
    syscall
    cmpq $0, %rax                 # Check return status (negative = error, zero = EOF/idle)
    js close_and_exit             # If error, exit loop
    jz listen_kernel              # If zero bytes read, continue listening loop               
    
    movq %rax, %r12               # Save actual number of bytes read
    movq $1, %rax                 # Syscall number 1: sys_write
    movq $1, %rdi                 # File descriptor 1: stdout
    leaq read_buf(%rip), %rsi     # Data buffer pointer
    movq %r12, %rdx               # Number of bytes to write
    syscall                       # Output received bytes directly to terminal
    jmp listen_kernel             # Continue infinite listening loop

# =====================================================================
# Program Exit and Error Handler Routines
# =====================================================================
close_and_exit:
    movq $3, %rax                 # Syscall number 3: sys_close
    movq fd(%rip), %rdi           # Serial port file descriptor argument
    syscall                       # Close serial port file descriptor
    
    movq $1, %rax                 # Syscall number 1: sys_write
    movq $1, %rdi                 # File descriptor 1: stdout
    leaq msg_close(%rip), %rsi    # Pointer to exit message string
    movq $len_close, %rdx         # Length of exit message
    syscall                       # Print exit message to terminal
    
    xorq %rdi, %rdi               # Exit code 0 (Success)
    jmp program_exit              # Jump to final program termination

open_failed:
    movq $1, %rax                 # Syscall number 1: sys_write
    movq $2, %rdi                 # File descriptor 2: stderr
    leaq msg_open_err(%rip), %rsi # Pointer to open error message string
    movq $len_open_err, %rdx      # Length of open error message
    syscall                       # Print error header
    
    movq $1, %rax                 # Syscall number 1: sys_write
    movq $2, %rdi                 # File descriptor 2: stderr
    movq dev_path_ptr(%rip), %rsi # Pointer to active device path string that failed
    movq $12, %rdx                # Length of device path string
    syscall                       # Print device path
    
    movq $1, %rax                 # Syscall number 1: sys_write
    movq $2, %rdi                 # File descriptor 2: stderr
    leaq newline_str(%rip), %rsi  # Pointer to newline character string
    movq $1, %rdx                 # Length of newline character
    syscall                       # Print newline character
    
    movq $60, %rax                # Syscall number 60: sys_exit
    movq $1, %rdi                 # Exit code 1 (General error)
    syscall                       # Terminate process with error code

sync_failed:
    movq $1, %rax                 # Syscall number 1: sys_write
    movq $2, %rdi                 # File descriptor 2: stderr (standard error)
    leaq msg_sync_err(%rip), %rsi # Pointer to synchronization error string
    movq $len_sync_err, %rdx      # Length of synchronization error string
    syscall                       # Print error message to stderr
    jmp close_and_exit            # Jump to cleanup and exit routine
    
program_exit:
    movq $60, %rax                # Syscall number 60: sys_exit
    syscall                       # Terminate process successfully

# =====================================================================
# Utility Subroutines - Serial I/O, Checksums, and Timing Control
# =====================================================================
send_packet_safe:
    pushq %rsi                    # Preserve buffer pointer register on stack
    pushq %rdx                    # Preserve length register on stack
    movq $1, %rax                 # Syscall number 1: sys_write
    movq fd(%rip), %rdi           # Serial port file descriptor argument
    popq %rdx                     # Restore length argument into %rdx
    popq %rsi                     # Restore buffer pointer argument into %rsi
    syscall                       # Write packet bytes to serial device
    ret                           # Return from subroutine

process_and_send_mem_data:
    pushq %rbx                    # Preserve callee-saved register %rbx
    pushq %r12                    # Preserve callee-saved register %r12
    pushq %r13                    # Preserve callee-saved register %r13
    pushq %r14                    # Preserve callee-saved register %r14
    
    movq kernel_size(%rip), %r12  # Load total payload size into %r12               
    leaq 16(%r12), %rax           # Add packet header overhead (16 bytes) to length
    movw %ax, mem_data_cmd+2(%rip)# Store length word into MEM_DATA command header
    movl %r12d, mem_data_cmd+8(%rip)# Store payload length into MEM_DATA command argument

    movl $0xEF, %ecx              # Initialize SLIP checksum initial seed value (0xEF)
    xorq %rax, %rax               # Clear accumulator register
    leaq payload_buf(%rip), %rbx  # Load base address of payload buffer into %rbx
    movq %r12, %r13               # Initialize loop counter with payload size
    
calc_sum:
    testq %r13, %r13              # Check if loop counter has reached zero
    jz save_checksum              # If zero, jump out of checksum loop
    movzbl (%rbx), %eax           # Load next single payload byte zero-extended
    xorl %eax, %ecx               # Accumulate byte into checksum using XOR
    incq %rbx                     # Advance buffer pointer to next byte
    decq %r13                     # Decrement loop counter
    jmp calc_sum                  # Repeat checksum calculation loop
    
save_checksum:
    movl %ecx, mem_data_cmd+4(%rip)# Store finalized checksum into command header
    
    # Send opening SLIP frame boundary delimiter (0xC0)
    leaq slip_boundary(%rip), %rsi# Pointer to boundary byte (0xC0)
    movq $1, %rdx                 # Length of 1 byte
    call send_packet_safe         # Send opening frame delimiter
    
    # Stream the MEM_DATA command header (24 bytes) with SLIP escaping
    leaq mem_data_cmd(%rip), %r14 # Pointer to command header bytes
    movq $24, %r13                # Length of command header (24 bytes)
    call stream_loop_escaped      # Stream escaped header bytes
    
    # Stream the actual payload buffer content with SLIP escaping
    leaq payload_buf(%rip), %r14  # Pointer to payload buffer
    movq %r12, %r13               # Length of payload size
    call stream_loop_escaped      # Stream escaped payload bytes
    
    # Send closing SLIP frame boundary delimiter (0xC0)
    leaq slip_boundary(%rip), %rsi# Pointer to boundary byte (0xC0)
    movq $1, %rdx                 # Length of 1 byte
    call send_packet_safe         # Send closing frame delimiter
    
    popq %r14                     # Restore callee-saved register %r14
    popq %r13                     # Restore callee-saved register %r13
    popq %r12                     # Restore callee-saved register %r12
    popq %rbx                     # Restore callee-saved register %rbx
    ret                           # Return from subroutine

stream_loop_escaped:
    testq %r13, %r13              # Check if byte counter has reached zero
    jz stream_done                # If zero, finish streaming loop
    movzbl (%r14), %eax           # Load current byte from stream buffer
    cmpb $0xC0, %al               # Compare byte with SLIP boundary value (0xC0)
    je escape_c0                  # If match, escape 0xC0 byte
    cmpb $0xDB, %al               # Compare byte with SLIP escape value (0xDB)
    je escape_db                  # If match, escape 0xDB byte
    
    # Transmit normal unescaped byte directly
    movq %r14, %rsi               # Pointer to current single byte
    movq $1, %rdx                 # Length of 1 byte
    call send_packet_safe         # Send byte over serial port
    jmp next_byte                 # Proceed to next byte

escape_c0:
    leaq slip_esc(%rip), %rsi     # Pointer to escape prefix byte (0xDB)
    movq $1, %rdx                 # Length of 1 byte
    call send_packet_safe         # Send escape prefix
    leaq slip_esc_c0(%rip), %rsi  # Pointer to escaped mapping byte (0xDC)
    movq $1, %rdx                 # Length of 1 byte
    call send_packet_safe         # Send mapped suffix byte
    jmp next_byte                 # Proceed to next byte

escape_db:
    leaq slip_esc(%rip), %rsi     # Pointer to escape prefix byte (0xDB)
    movq $1, %rdx                 # Length of 1 byte
    call send_packet_safe         # Send escape prefix
    leaq slip_esc_db(%rip), %rsi  # Pointer to escaped mapping byte (0xDD)
    movq $1, %rdx                 # Length of 1 byte
    call send_packet_safe         # Send mapped suffix byte
    jmp next_byte                 # Proceed to next byte

next_byte:
    incq %r14                     # Advance source pointer to next byte
    decq %r13                     # Decrement remaining byte counter
    jmp stream_loop_escaped       # Repeat streaming loop

stream_done:
    ret                           # Return from subroutine

do_sleep_100ms:
    movq $35, %rax                # Syscall number 35: sys_nanosleep
    leaq sleep_100ms_ts(%rip), %rdi# Pointer to 100ms timespec struct
    xorq %rsi, %rsi               # NULL argument for remaining time
    syscall                       # Execute system call to sleep
    ret                           # Return from subroutine

do_sleep_200ms:
    movq $35, %rax                # Syscall number 35: sys_nanosleep
    leaq sleep_200ms_ts(%rip), %rdi# Pointer to 200ms timespec struct
    xorq %rsi, %rsi               # NULL argument for remaining time
    syscall                       # Execute system call to sleep
    ret                           # Return from subroutine
