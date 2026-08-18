# ==============================================================================
# Project:     Standalone ESP32-C3 Vectorized Checksum Utility
# Name:        esp32c3_checksum.s
# Target:      x86_64 Linux (Pure Assembly, No C Library, ABI/Stack Proof)
# Description: 128-bit Vectorized ESP32-C3 XOR Checksum Subroutine
# Architecture: x86_64 (System V ABI)
#
# Inputs: %rdi = memory buffer pointer, %rsi = buffer length
# Output: %al  = 8-bit XOR checksum
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

.section .text
.globl esp32c3_checksum
.type esp32c3_checksum, @function

esp32c3_checksum:
    .cfi_startproc
    movq $0x00000000000000EF, %rax     # Initialize %rax with the mandatory ESP32-C3 checksum seed (0xEF)
    testq %rsi, %rsi                   # Test if the buffer length (%rsi) is zero
    jz .checksum_done                  # If length is zero, jump straight to the end (returning 0xEF)

    leaq 15(%rsi), %rcx                # Add 15 to the length to prepare for ceiling division
    shrq $4, %rcx                      # Shift right by 4 (divide by 16) to get the exact number of 16-byte chunks

    pxor %xmm0, %xmm0                  # Clear the 128-bit XMM0 accumulator register to all zeros

.vector_chunk_loop:
    movdqu (%rdi), %xmm1               # Load 16 unaligned bytes from the memory buffer into XMM1
    pxor %xmm1, %xmm0                  # XOR the 16 bytes simultaneously into the XMM0 accumulator
    addq $16, %rdi                     # Advance the buffer pointer by 16 bytes
    decq %rcx                          # Decrement the chunk counter
    jnz .vector_chunk_loop             # If counter > 0, loop back to process the next chunk

.fold_reduction:
    # --------------------------------------------------------------------------
    # Horizontal Tree Folding: Reduce 128 bits down to 8 bits
    # --------------------------------------------------------------------------
    movq %xmm0, %r8                    # Extract the lower 64 bits of XMM0 into %r8
    pshufd $0x4E, %xmm0, %xmm1         # Shuffle XMM0 (0x4E = swap upper/lower halves) and store in XMM1
    movq %xmm1, %r9                    # Extract the upper 64 bits (now in the lower half of XMM1) into %r9
    xorq %r9, %r8                      # XOR the upper 64 bits with the lower 64 bits; result in %r8
    
    # Inject the ESP32-C3 Seed
    xorq %r8, %rax                     # XOR the folded 64 bits into %rax (which safely holds our 0xEF seed at the bottom)

    # Fold 64-bit %rax down to 32-bit
    movq %rax, %r8                     # Copy the 64-bit accumulator to %r8
    shrq $32, %r8                      # Shift the upper 32 bits down to the lower half
    xorl %r8d, %eax                    # XOR the upper 32 bits with the lower 32 bits (%eax)

    # Fold 32-bit %eax down to 16-bit
    movl %eax, %r8d                    # Copy the 32-bit accumulator to %r8d
    shrl $16, %r8d                     # Shift the upper 16 bits down to the lower half
    xorw %r8w, %ax                     # XOR the upper 16 bits with the lower 16 bits (%ax)

    # Fold 16-bit %ax down to 8-bit
    movw %ax, %r8w                     # Copy the 16-bit accumulator to %r8w
    shrw $8, %r8w                      # Shift the upper 8 bits down to the lower half
    xorb %r8b, %al                     # XOR the upper 8 bits with the lower 8 bits (%al)

.checksum_done:
    ret                                # Return from subroutine. Final 8-bit checksum safely rests in %al.
    .cfi_endproc

.section .note.GNU-stack,"",@progbits  # Mark stack as non-executable for Linux security
