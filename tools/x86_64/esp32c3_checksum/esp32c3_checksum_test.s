# ==============================================================================
# Project:     Standalone ESP32-C3 Vectorized Checksum Utility
# Target:      x86_64 Linux (Pure Assembly, No C Library, ABI/Stack Proof)
# Description: Test wrapper program for espc32c3_checksum
# Architecture: x86_64 (System V ABI)
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
# ==============================================================================

.global _start
.extern esp32c3_checksum
.extern bin2hexascii_uint8

# System call numbers for x86_64 Linux
.equ SYS_write,   1
.equ SYS_open,    2
.equ SYS_close,   3
.equ SYS_lseek,   8
.equ SYS_mmap,    9
.equ SYS_munmap,  11
.equ SYS_exit,    60

# Constants for memory mapping and file seeking
.equ PROT_READ,   0x1
.equ MAP_PRIVATE, 0x02
.equ SEEK_END,    2

.section .text

# Static strings and their calculated lengths
msg_usage:    .ascii "Usage: esp32c_checksum_tool <binary>\n"
len_usage     = . - msg_usage

msg_err_io:   .ascii "Error: File I/O failed.\n"
len_err_io    = . - msg_err_io

msg_result:   .ascii "ESP32-C3 Checksum (Hex): 0x"
len_result    = . - msg_result

newline:      .ascii "\n"

# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================
_start:
    # --- 1. Arguments Parsing ---
    movq (%rsp), %rax              # Load argc (argument count) from the stack into %rax
    cmpq $2, %rax                  # Compare argc with 2 (program name + 1 argument)
    jl err_arguments               # If argc < 2, jump to err_arguments to show usage
    movq 16(%rsp), %r15            # Load argv[1] (pointer to filename string) into %r15

    # --- 2. File I/O & Memory Mapping ---
    movq $SYS_open, %rax           # Prepare syscall number for sys_open (2)
    movq %r15, %rdi                # Set arg1: pointer to filename string
    xorq %rsi, %rsi                # Set arg2: flags = 0 (O_RDONLY)
    xorq %rdx, %rdx                # Set arg3: mode = 0 (not creating a file)
    syscall                        # Execute sys_open
    cmpq $0, %rax                  # Check if returned file descriptor is negative
    jl err_io_handler              # If negative, file open failed; jump to error handler
    movq %rax, %r12                # Save valid file descriptor securely in %r12

    movq $SYS_lseek, %rax          # Prepare syscall number for sys_lseek (8)
    movq %r12, %rdi                # Set arg1: file descriptor
    xorq %rsi, %rsi                # Set arg2: offset = 0
    movq $SEEK_END, %rdx           # Set arg3: whence = SEEK_END (seek to end of file)
    syscall                        # Execute sys_lseek (returns total file size in bytes)
    cmpq $0, %rax                  # Check if returned size is negative
    jl err_io_handler              # If negative, seek failed; jump to error handler
    movq %rax, %r13                # Save exact file size securely in %r13

    # Calculate 16-byte padded size for safe vectorized reads
    movq %r13, %r14                # Copy exact file size into %r14
    addq $15, %r14                 # Add 15 bytes to force rounding up
    andq $-16, %r14                # Mask out the lowest 4 bits to align to 16-byte boundary

    movq $SYS_mmap, %rax           # Prepare syscall number for sys_mmap (9)
    xorq %rdi, %rdi                # Set arg1: addr = NULL (let kernel choose address)
    movq %r14, %rsi                # Set arg2: length = 16-byte padded size
    movq $PROT_READ, %rdx          # Set arg3: prot = PROT_READ (read-only memory)
    movq $MAP_PRIVATE, %r10        # Set arg4: flags = MAP_PRIVATE (private copy-on-write)
    movq %r12, %r8                 # Set arg5: fd = our open file descriptor
    xorq %r9, %r9                  # Set arg6: offset = 0 (start mapping from beginning of file)
    syscall                        # Execute sys_mmap
    cmpq $-1, %rax                 # Check if mmap returned MAP_FAILED (-1)
    je err_io_handler              # If mapping failed, jump to error handler
    movq %rax, %r15                # Save memory map base address securely in %r15

    movq $SYS_close, %rax          # Prepare syscall number for sys_close (3)
    movq %r12, %rdi                # Set arg1: our open file descriptor
    syscall                        # Execute sys_close (file stays mapped in memory)

    # --- 3. Compute Checksum (Calling External Library) ---
    movq %r15, %rdi                # Set arg1 for subroutine: memory map base address
    movq %r13, %rsi                # Set arg2 for subroutine: exact unpadded file size
    call esp32c3_checksum          # Execute the external 128-bit vectorized checksum routine
    movzbq %al, %r12               # Save returned 8-bit checksum securely into %r12

    # --- 4. Print Results (Calling External Library) ---
    movq $SYS_write, %rax          # Prepare syscall number for sys_write (1)
    movq $1, %rdi                  # Set arg1: file descriptor 1 (STDOUT)
    leaq msg_result(%rip), %rsi    # Set arg2: pointer to the "ESP32-C3 Checksum (Hex): 0x" string
    movq $len_result, %rdx         # Set arg3: length of the result string
    syscall                        # Execute sys_write

    movzbl %r12b, %edi             # Zero-extend the 8-bit checksum into %edi for the hex converter
    call bin2hexascii_uint8        # Execute external hex converter (returns 16-bit ASCII in %ax)
    xchgb %ah, %al                 # Swap high/low bytes in %ax to correct little-endian ordering
    
    pushq %rax                     # Push the 2 ASCII characters onto the stack memory
    movq $SYS_write, %rax          # Prepare syscall number for sys_write (1)
    movq $1, %rdi                  # Set arg1: file descriptor 1 (STDOUT)
    movq %rsp, %rsi                # Set arg2: pointer to the stack where our characters live
    movq $2, %rdx                  # Set arg3: length = 2 bytes
    syscall                        # Execute sys_write to print the hex digits
    popq %rax                      # Pop the stack to restore the stack pointer

    movq $SYS_write, %rax          # Prepare syscall number for sys_write (1)
    movq $1, %rdi                  # Set arg1: file descriptor 1 (STDOUT)
    leaq newline(%rip), %rsi       # Set arg2: pointer to the newline string
    movq $1, %rdx                  # Set arg3: length = 1 byte
    syscall                        # Execute sys_write

    # --- 5. Cleanup ---
    movq $SYS_munmap, %rax         # Prepare syscall number for sys_munmap (11)
    movq %r15, %rdi                # Set arg1: memory map base address
    movq %r14, %rsi                # Set arg2: 16-byte padded size mapped earlier
    syscall                        # Execute sys_munmap to free memory

    movq %r12, %rdi                # Move the 8-bit checksum into %rdi to act as process exit code
    movq $SYS_exit, %rax           # Prepare syscall number for sys_exit (60)
    syscall                        # Execute sys_exit

# ==============================================================================
# ERROR HANDLERS
# ==============================================================================
err_arguments:
    movq $SYS_write, %rax          # Prepare syscall number for sys_write (1)
    movq $2, %rdi                  # Set arg1: file descriptor 2 (STDERR)
    leaq msg_usage(%rip), %rsi     # Set arg2: pointer to the usage string
    movq $len_usage, %rdx          # Set arg3: length of the usage string
    syscall                        # Execute sys_write
    movq $SYS_exit, %rax           # Prepare syscall number for sys_exit (60)
    movq $1, %rdi                  # Set arg1: exit code = 1 (failure)
    syscall                        # Execute sys_exit

err_io_handler:
    movq $SYS_write, %rax          # Prepare syscall number for sys_write (1)
    movq $2, %rdi                  # Set arg1: file descriptor 2 (STDERR)
    leaq msg_err_io(%rip), %rsi    # Set arg2: pointer to the I/O error string
    movq $len_err_io, %rdx         # Set arg3: length of the I/O error string
    syscall                        # Execute sys_write
    movq $SYS_exit, %rax           # Prepare syscall number for sys_exit (60)
    movq $1, %rdi                  # Set arg1: exit code = 1 (failure)
    syscall                        # Execute sys_exit

.section .note.GNU-stack,"",@progbits
