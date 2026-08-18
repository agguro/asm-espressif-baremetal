# =====================================================================
# Project:     Bare-Metal ESP32-C3 x86_64 Host Patcher & Formatter
# Name:        esp32c3_flash.s
# Author:      agguro
# Date:        August 14, 2026
# Description: Pure x86_64 assembly tool to convert a raw binary (.bin)
#              into a fully compliant ESP32-C3 boot image (adding 32-byte 
#              header, padding to 16-byte boundary, and XOR checksum).
#
# Copyright 2026 agguro
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# =====================================================================

.global _start

.section .data
    msg_usage:    .string "Usage: esp32c3_flash [--flash | --sram] <binary>\n"
    len_usage     = . - msg_usage - 1

    msg_err_open: .string "Error: Could not open input file.\n"
    len_err_open  = . - msg_err_open - 1

    msg_err_write:.string "Error: Could not write output file.\n"
    len_err_write = . - msg_err_write - 1

    msg_ok:       .string "[FLASH] ESP32-C3 image successfully formatted: "
    len_ok        = . - msg_ok

    newline:      .string "\n"
    len_nl        = 1

    # Suffixes for output files
    suffix_flash: .string "_flash.bin"
    suffix_sram:  .string "_sram.bin"

    # ESP32-C3 Image Header Template (24 bytes) + Segment Header (8 bytes) = 32 bytes total
    esp_template:
        .byte 0xE9                 # 0x00: Magic byte
        .byte 1                    # 0x01: Number of segments
        .byte 2                    # 0x02: SPI flash mode (DIO)
        .byte 0                    # 0x03: SPI flash speed/size
        .long 0x40380000           # 0x04: Entry point address (4 bytes)
        .long 0                    # 0x08: WP pin settings (4 bytes)
        .word 5                    # 0x0C: Chip ID (5 = ESP32-C3) (2 bytes)
        .byte 0                    # 0x0E: Min chip rev (1 byte)
        .word 0                    # 0x0F: Min rev full (2 bytes)
        .word 0                    # 0x11: Max rev full (2 bytes)
        .word 0                    # 0x13: Reserved bytes (2 bytes)
        .byte 0                    # 0x15: Digest flag (1 byte)
        .byte 0, 0                 # 0x16: Padding alignment (2 bytes)
        # Segment Header (8 bytes)
        .long 0x40380000           # 0x18: Target load address (4 bytes)
        .long 0                    # 0x1C: Segment length (4 bytes, dynamic)

.section .bss
    .lcomm input_fd, 8
    .lcomm output_fd, 8
    .lcomm file_size, 8
    .lcomm target_addr, 4
    .lcomm input_path, 8
    .lcomm output_path, 256
    .lcomm work_buf, 1048576       # 1MB buffer for binary payload + formatting

.section .text
_start:
    # -----------------------------------------------------------------
    # Step 1: Parse Arguments (argc, argv)
    # -----------------------------------------------------------------
    movq (%rsp), %rax             # argc
    cmpq $2, %rax
    jl show_usage

    leaq 16(%rsp), %r9            # argv pointer array
    movq (%r9), %rsi              # argv[1]

    # Check if argv[1] starts with '-'
    movb (%rsi), %al
    cmpb $0x2d, %al               # '-'
    jne default_mode

    # Check flag type (--flash vs --sram)
    movb 2(%rsi), %al             # third character
    cmpb $0x66, %al               # 'f' in --flash
    je mode_flash

    # Default to sram suffix if not flash flag
    jmp mode_sram

mode_flash:
    cmpq $3, %rax
    jl show_usage
    movq 8(%r9), %rsi             # argv[2]
    movq %rsi, input_path(%rip)
    call build_output_path_flash
    jmp open_files

mode_sram:
    cmpq $3, %rax
    jl show_usage
    movq 8(%r9), %rsi             # argv[2]
    movq %rsi, input_path(%rip)
    call build_output_path_sram
    jmp open_files

default_mode:
    # Single argument format: esp32c3_flash $(BIN) -> defaults to _flash.bin
    movq %rsi, input_path(%rip)
    call build_output_path_flash
    jmp open_files

# -----------------------------------------------------------------
# Helper Subroutines: Path String Construction
# -----------------------------------------------------------------
build_output_path_flash:
    movq input_path(%rip), %rsi
    leaq output_path(%rip), %rdi
    call string_copy
    leaq suffix_flash(%rip), %rsi
    leaq output_path(%rip), %rdi
    call string_append
    ret

build_output_path_sram:
    movq input_path(%rip), %rsi
    leaq output_path(%rip), %rdi
    call string_copy
    leaq suffix_sram(%rip), %rsi
    leaq output_path(%rip), %rdi
    call string_append
    ret

string_copy:
    lodsb
    stosb
    testb %al, %al
    jnz string_copy
    decq %rdi
    ret

string_append:
.append_loop:
    lodsb
    stosb
    testb %al, %al
    jnz .append_loop
    ret

# -----------------------------------------------------------------
# Step 2: File I/O (Open, Size, Read, Close)
# -----------------------------------------------------------------
open_files:
    # Open input file (O_RDONLY = 0)
    movq $2, %rax                 # sys_open
    movq input_path(%rip), %rdi
    xorq %rsi, %rsi
    xorq %rdx, %rdx
    syscall
    cmpq $0, %rax
    js err_open
    movq %rax, input_fd(%rip)

    # Get file size via sys_lseek
    movq $8, %rax                 # sys_lseek
    movq input_fd(%rip), %rdi
    xorq %rsi, %rsi
    movq $2, %rdx                 # SEEK_END
    syscall
    movq %rax, file_size(%rip)

    # Rewind input file offset
    movq $8, %rax                 # sys_lseek
    movq input_fd(%rip), %rdi
    xorq %rsi, %rsi
    xorq %rdx, %rdx               # SEEK_SET
    syscall

    # Read binary payload into work_buf offset by 32 bytes
    movq $0, %rax                 # sys_read
    movq input_fd(%rip), %rdi
    leaq work_buf+32(%rip), %rsi
    movq file_size(%rip), %rdx
    syscall

    # Close input file
    movq $3, %rax                 # sys_close
    movq input_fd(%rip), %rdi
    syscall

    # -----------------------------------------------------------------
    # Step 3: Populate Headers & Segment Length
    # -----------------------------------------------------------------
    leaq esp_template(%rip), %rsi
    leaq work_buf(%rip), %rdi
    movq $32, %rcx
    rep movsb

    # Insert dynamic segment length at offset 28
    movq file_size(%rip), %rax
    movl %eax, work_buf+28(%rip)

    # -----------------------------------------------------------------
    # Step 4: Calculate 16-Byte Padding Alignment
    # -----------------------------------------------------------------
    movq $32, %rax
    addq file_size(%rip), %rax    # total current length
    
    movq %rax, %rcx
    andq $15, %rcx                # current length % 16
    
    movq $15, %rdx
    subq %rcx, %rdx
    andq $15, %rdx                # pad_len in %rdx

    # Zero out pad_len bytes
    leaq work_buf(%rip), %rdi
    addq %rax, %rdi
    movq %rdx, %rcx
    xorq %rax, %rax
.pad_loop:
    testq %rcx, %rcx
    jz .pad_done
    movb %al, (%rdi)
    incq %rdi
    decq %rcx
    jmp .pad_loop
.pad_done:
    # Final payload length before checksum byte
    movq $32, %r8
    addq file_size(%rip), %r8
    addq %rdx, %r8                # index for checksum byte

    # -----------------------------------------------------------------
    # Step 5: Compute XOR Checksum (Seed = 0xEF, range: byte 32 to padding end)
    # -----------------------------------------------------------------
    movl $0xEF, %ecx              # initial seed
    leaq work_buf+32(%rip), %rsi
    movq %r8, %r9
    subq $32, %r9
.chk_loop:
    testq %r9, %r9
    jz .chk_done
    movzbl (%rsi), %eax
    xorl %eax, %ecx
    incq %rsi
    decq %r9
    jmp .chk_loop
.chk_done:
    # Append single checksum byte at the end
    leaq work_buf(%rip), %rdi
    addq %r8, %rdi
    movb %cl, (%rdi)
    incq %r8                      # total output size including checksum byte

    # -----------------------------------------------------------------
    # Step 6: Write Final Formatted Image to Disk
    # -----------------------------------------------------------------
    movq $2, %rax                 # sys_open
    leaq output_path(%rip), %rdi
    movq $0102, %rsi              # O_CREAT | O_WRONLY
    movq $0644, %rdx              # permissions rw-r--r--
    syscall
    cmpq $0, %rax
    js err_write
    movq %rax, output_fd(%rip)

    movq $1, %rax                 # sys_write
    movq output_fd(%rip), %rdi
    leaq work_buf(%rip), %rsi
    movq %r8, %rdx
    syscall

    movq $3, %rax                 # sys_close
    movq output_fd(%rip), %rdi
    syscall

    # Print success output
    movq $1, %rax
    movq $1, %rdi
    leaq msg_ok(%rip), %rsi
    movq $len_ok, %rdx
    syscall

    call print_output_path

    movq $1, %rax
    movq $1, %rdi
    leaq newline(%rip), %rsi
    movq $len_nl, %rdx
    syscall

    xorq %rdi, %rdi
    movq $60, %rax
    syscall

# -----------------------------------------------------------------
# Utility & Error Handlers
# -----------------------------------------------------------------
print_output_path:
    leaq output_path(%rip), %rsi
    xorq %rdx, %rdx
.len_str_loop:
    movb (%rsi,%rdx,1), %al
    testb %al, %al
    jz .len_str_done
    incq %rdx
    jmp .len_str_loop
.len_str_done:
    movq $1, %rax
    movq $1, %rdi
    leaq output_path(%rip), %rsi
    syscall
    ret

show_usage:
    movq $1, %rax
    movq $1, %rdi
    leaq msg_usage(%rip), %rsi
    movq $len_usage, %rdx
    syscall
    movq $60, %rax
    movq $1, %rdi
    syscall

err_open:
    movq $1, %rax
    movq $2, %rdi
    leaq msg_err_open(%rip), %rsi
    movq $len_err_open, %rdx
    syscall
    movq $60, %rax
    movq $1, %rdi
    syscall

err_write:
    movq $1, %rax
    movq $2, %rdi
    leaq msg_err_write(%rip), %rsi
    movq $len_err_write, %rdx
    syscall
    movq $60, %rax
    movq $1, %rdi
    syscall
