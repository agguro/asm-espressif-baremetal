# ==============================================================================
# Project:     Standalone ESP32-C3 Vectorized Checksum Utility
# File:        bin2hexascii_uint8.s
# Author:      agguro
# Date:        August 14, 2026   
# Description: Branchless binary to hex-ASCII conversion.
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

.section .text

# ------------------------------------------------------------------------------
# Subroutine: bin2hexascii_uint8
# In  : %dil (8-bit binary input)
# Out : %ax  (16-bit ASCII output: %ah = High nibble char, %al = Low nibble char)
# ------------------------------------------------------------------------------
.globl bin2hexascii_uint8
.type bin2hexascii_uint8, @function
bin2hexascii_uint8:
    .cfi_startproc
    # --- Isolate High and Low Nibbles ---
    movzbl  %dil, %edi             # Zero-extend the 8-bit input (%dil) into 32-bit (%edi)
    movl    %edi, %eax             # Make a working copy of the input in %eax
    shrb    $4, %al                # Shift %al right by 4 to isolate the High Nibble (0-15)
    andb    $0x0F, %dil            # Mask %dil with 0x0F to isolate the Low Nibble (0-15)
    
    # --- Convert High Nibble (%al) to ASCII ---
    cmpb    $10, %al               # Compare the High Nibble value to 10
    setge   %cl                    # Set %cl to 1 if %al >= 10 (A-F), else set to 0 (0-9)
    movzbl  %cl, %ecx              # Zero-extend the boolean flag in %cl into %ecx
    imull   $7, %ecx, %ecx         # Multiply flag by 7. (If A-F, %ecx = 7. If 0-9, %ecx = 0)
    addb    $'0', %al              # Add ASCII base '0' (0x30) to the nibble value
    addb    %cl, %al               # Add the 7 offset if it was A-F (bridges gap between '9' and 'A')
    
    # --- Convert Low Nibble (%dil) to ASCII ---
    cmpb    $10, %dil              # Compare the Low Nibble value to 10
    setge   %cl                    # Set %cl to 1 if %dil >= 10 (A-F), else set to 0 (0-9)
    movzbl  %cl, %ecx              # Zero-extend the boolean flag in %cl into %ecx
    imull   $7, %ecx, %ecx         # Multiply flag by 7. (If A-F, %ecx = 7. If 0-9, %ecx = 0)
    addb    $'0', %dil             # Add ASCII base '0' (0x30) to the nibble value
    addb    %cl, %dil              # Add the 7 offset if it was A-F
    
    # --- Pack Results into %ax ---
    shll    $8, %eax               # Shift the High Nibble ASCII character up into %ah
    movb    %dil, %al              # Move the Low Nibble ASCII character into %al
    ret                            # Return. %ax now holds the packed 16-bit ASCII representation
    .cfi_endproc

.section .note.GNU-stack,"",@progbits  # Mark stack as non-executable for Linux security
