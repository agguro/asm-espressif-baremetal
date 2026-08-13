# =====================================================================
# Project:      Bare-Metal ESP32-C3 Host Loader (Native USB-JTAG)
# Name:         esp32c3_host.s
# Architecture: x86_64
# Author:       agguro
# Date:         August 13, 2026
# Description:  Pure x86_64 assembly Linux host tool to push a RISC-V 
#               kernel to the ESP32-C3 SRAM via SLIP-escaped protocol. 
#               It connects to 'esp32c3_kernel.bin', which should be a 
#               symlink to your actual compiled bare-metal ESP32-C3 
#               program. It forces a hardware reset, uploads the kernel, 
#               executes it, and streams the Native USB serial output.
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

.section .bss
    .lcomm fd, 8
    .lcomm read_buf, 256        
    .lcomm termios, 60            

.section .rodata
    dev_path:      .string "/dev/ttyACM1"
    
    msg_open_err:  .string "Error: Could not open port /dev/ttyACM0.\n"
    len_open_err = . - msg_open_err - 1

    msg_open_ok:   .string "[HOST] Port opened & Native USB-JTAG reset executed.\n"
    len_open_ok  = . - msg_open_ok - 1

    msg_upload:    .string "[HOST] Uploading SLIP-escaped RISC-V kernel...\n"
    len_upload   = . - msg_upload - 1

    msg_running:   .string "[HOST] Kernel execution started! Listening for output (Ctrl+C to exit)...\n"
    len_running  = . - msg_running - 1

    msg_close:     .string "\n[HOST] Port successfully closed. Program exits.\n"
    len_close    = . - msg_close - 1

    # Nanosleep timestamps for reliable hardware reset
    sleep_100ms_ts: .quad 0, 100000000
    sleep_200ms_ts: .quad 0, 200000000

    # Fully Validated SLIP-Framed ROM-Bootloader Packets
    sync_packet:
        .byte 0xC0                    
        .byte 0x00, 0x08              # ESP_SYNC
        .2byte 36                     
        .4byte 0                      
        .byte 0x07, 0x07, 0x12, 0x20  
        .fill 32, 1, 0x55             
        .byte 0xC0                    
    sync_len = . - sync_packet

    attach_packet:
        .byte 0xC0                    
        .byte 0x00, 0x0B              # ESP_SPI_ATTACH
        .2byte 8                      
        .4byte 0                      
        .4byte 0, 0                   
        .byte 0xC0                    
    attach_len = . - attach_packet

    mem_begin_packet:
        .byte 0xC0                    
        .byte 0x00, 0x05              # ESP_MEM_BEGIN (SRAM)
        .2byte 16                     
        .4byte 0                      
        .4byte kernel_end - kernel_start  
        .4byte 1                      
        .4byte 0x400                  
        .4byte 0x40380000             
        .byte 0xC0                    
    mem_begin_len = . - mem_begin_packet

    run_packet:
        .byte 0xC0                    
        .byte 0x00, 0x06              # ESP_MEM_END
        .2byte 8                      
        .4byte 0                      
        .4byte 0                      
        .4byte 0x40380000             
        .byte 0xC0                    
    run_len = . - run_packet
    
.section .data
    # -----------------------------------------------------------------
    # THE PAYLOAD: Embed the RISC-V kernel binary via symlink
    # -----------------------------------------------------------------
    kernel_start:
        .incbin "esp32c3_kernel.bin"
    kernel_end:

    slip_boundary:    .byte 0xC0
    slip_esc:         .byte 0xDB
    slip_esc_c0:      .byte 0xDC
    slip_esc_db:      .byte 0xDD

    mem_data_cmd: 
        .byte 0x00, 0x07              # ESP_MEM_DATA
        .2byte 0                      
        .4byte 0                      
        .4byte 0                      
        .4byte 0                      
        .4byte 0, 0                   

.section .text
_start:
    # 1. Open target serial character device interface
    movq $2, %rax                
    leaq dev_path(%rip), %rdi
    movq $2, %rsi                
    movq $0, %rdx
    syscall
    cmpq $0, %rax
    js open_failed          
    movq %rax, fd(%rip)     

    # 1.1 HARDWARE SEQUENCE: ESP32-C3 Native USB-JTAG "CustomReset"
    subq $8, %rsp
    
    # Step 1: DTR=0, RTS=0
    movl $0x006, (%rsp)
    movq $16, %rax; movq fd(%rip), %rdi; movq $0x5417, %rsi; movq %rsp, %rdx; syscall
    call do_sleep_100ms
    
    # Step 2: DTR=1, RTS=0
    movl $0x002, (%rsp)
    movq $16, %rax; movq fd(%rip), %rdi; movq $0x5416, %rsi; movq %rsp, %rdx; syscall
    movl $0x004, (%rsp)
    movq $16, %rax; movq fd(%rip), %rdi; movq $0x5417, %rsi; movq %rsp, %rdx; syscall
    call do_sleep_100ms
    
    # Step 3: RTS=1 (DTR remains 1)
    movl $0x004, (%rsp)
    movq $16, %rax; movq fd(%rip), %rdi; movq $0x5416, %rsi; movq %rsp, %rdx; syscall
    
    # Step 4: DTR=0 (RTS remains 1)
    movl $0x002, (%rsp)
    movq $16, %rax; movq fd(%rip), %rdi; movq $0x5417, %rsi; movq %rsp, %rdx; syscall
    
    # Step 5: RTS=0 (Both are 0 now)
    movl $0x004, (%rsp)
    movq $16, %rax; movq fd(%rip), %rdi; movq $0x5417, %rsi; movq %rsp, %rdx; syscall
    
    addq $8, %rsp
    call do_sleep_200ms

    # 2. Reconfigure tty layer structure safely to RAW mode
    movq $16, %rax; movq fd(%rip), %rdi; movq $0x5401, %rsi; leaq termios(%rip), %rdx; syscall
    movl $0, termios+0(%rip); movl $0, termios+4(%rip); movl $0, termios+12(%rip); movl $0x000018B2, termios+8(%rip) 
    
    # SETUP FOR UPLOAD: Non-blocking with 200ms timeout
    movb $2, termios+22(%rip); movb $0, termios+23(%rip)
    movq $16, %rax; movq fd(%rip), %rdi; movq $0x5402, %rsi; leaq termios(%rip), %rdx; syscall

    # IMPORTANT: Drain ASCII logs produced during the bootloader reset
drain_logs:
    movq $0, %rax; movq fd(%rip), %rdi; leaq read_buf(%rip), %rsi; movq $256, %rdx; syscall
    cmpq $0, %rax; jg drain_logs

    movq $1, %rax; movq $1, %rdi; leaq msg_open_ok(%rip), %rsi; movq $len_open_ok, %rdx; syscall

    # 3. Synchronize handshaking loops safely
    movq $50, %r13                  
send_sync_loop:
    decq %r13; js sync_failed                  
    leaq sync_packet(%rip), %rsi; movq $sync_len, %rdx; call send_packet_safe
    movq $0, %rax; movq fd(%rip), %rdi; leaq read_buf(%rip), %rsi; movq $64, %rdx; syscall
    cmpq $0, %rax; jle send_sync_loop             
    movzbq read_buf+2(%rip), %rax; cmpq $0x08, %rax; jne send_sync_loop
    
    # 4. Issue standard SPI Peripheral Attach command sequence
    leaq attach_packet(%rip), %rsi; movq $attach_len, %rdx; call send_packet_safe
read_attach_retry:
    movq $0, %rax; movq fd(%rip), %rdi; leaq read_buf(%rip), %rsi; movq $32, %rdx; syscall
    cmpq $0, %rax; jle read_attach_retry

    movq $1, %rax; movq $1, %rdi; leaq msg_upload(%rip), %rsi; movq $len_upload, %rdx; syscall

    # 5. Issue Allocation Base Initialization Block (MEM_BEGIN)
    leaq mem_begin_packet(%rip), %rsi; movq $mem_begin_len, %rdx; call send_packet_safe
read_mem_begin_retry:
    movq $0, %rax; movq fd(%rip), %rdi; leaq read_buf(%rip), %rsi; movq $32, %rdx; syscall
    cmpq $0, %rax; jle read_mem_begin_retry

    # 6. Stream kernel payload bytes (MEM_DATA)
    call process_and_send_mem_data
read_mem_data_retry:
    movq $0, %rax; movq fd(%rip), %rdi; leaq read_buf(%rip), %rsi; movq $32, %rdx; syscall
    cmpq $0, %rax; jle read_mem_data_retry

    # 7. Execute Program Run Command vector target
    leaq run_packet(%rip), %rsi; movq $run_len, %rdx; call send_packet_safe

    # Give the ROM bootloader time to acknowledge the execute command
    call do_sleep_100ms

    # Swallow the final ACK containing 0xC0 and discard it safely
drain_final_ack:
    movq $0, %rax
    movq fd(%rip), %rdi
    leaq read_buf(%rip), %rsi
    movq $64, %rdx              
    syscall
    cmpq $0, %rax
    jg drain_final_ack

    # Switch termios to BLOCKING read mode for active kernel execution
    movq $16, %rax; movq fd(%rip), %rdi; movq $0x5401, %rsi; leaq termios(%rip), %rdx; syscall
    
    # SETUP FOR RECEIVE: Blocking, wait for at least 1 character
    movb $0, termios+22(%rip); movb $1, termios+23(%rip)
    movq $16, %rax; movq fd(%rip), %rdi; movq $0x5402, %rsi; leaq termios(%rip), %rdx; syscall

    # Notify the user that the kernel is now running
    movq $1, %rax; movq $1, %rdi; leaq msg_running(%rip), %rsi; movq $len_running, %rdx; syscall

# 8. Redirect all incoming kernel execution output directly to stdout
listen_kernel:
    movq $0, %rax; movq fd(%rip), %rdi; leaq read_buf(%rip), %rsi; movq $256, %rdx; syscall
    cmpq $0, %rax; js close_and_exit; jz listen_kernel               
    movq %rax, %r12
    movq $1, %rax; movq $1, %rdi; leaq read_buf(%rip), %rsi; movq %r12, %rdx; syscall
    jmp listen_kernel

close_and_exit:
    movq $3, %rax; movq fd(%rip), %rdi; syscall
    movq $1, %rax; movq $1, %rdi; leaq msg_close(%rip), %rsi; movq $len_close, %rdx; syscall
    xorq %rdi, %rdi; jmp program_exit

open_failed:
    movq $1, %rax; movq $2, %rdi; leaq msg_open_err(%rip), %rsi; movq $len_open_err, %rdx; syscall
    movq $60, %rax; movq $1, %rdi; syscall
sync_failed:
    movq $1, %rax; movq $2, %rdi; jmp close_and_exit
program_exit:
    movq $60, %rax; syscall

# =========================================================================
# SYSTEM CORE UTILITY ROUTINES
# =========================================================================
send_packet_safe:
    pushq %rsi; pushq %rdx
    movq $1, %rax; movq fd(%rip), %rdi; popq %rdx; popq %rsi; syscall
    ret

process_and_send_mem_data:
    pushq %rbx; pushq %r12; pushq %r13; pushq %r14
    leaq kernel_start(%rip), %rax; leaq kernel_end(%rip), %rcx; subq %rax, %rcx; movq %rcx, %r12                
    leaq 16(%r12), %rax; movw %ax, mem_data_cmd+2(%rip)
    movl %r12d, mem_data_cmd+8(%rip)
    movl $0xEF, %ecx; xorq %rax, %rax; leaq kernel_start(%rip), %rbx; movq %r12, %r13
calc_sum:
    testq %r13, %r13; jz save_checksum
    movzbl (%rbx), %eax; xorl %eax, %ecx; incq %rbx; decq %r13; jmp calc_sum
save_checksum:
    movl %ecx, mem_data_cmd+4(%rip)
    leaq slip_boundary(%rip), %rsi; movq $1, %rdx; call send_packet_safe
    leaq mem_data_cmd(%rip), %r14; movq $24, %r13; call stream_loop_escaped
    leaq kernel_start(%rip), %r14; movq %r12, %r13; call stream_loop_escaped
    leaq slip_boundary(%rip), %rsi; movq $1, %rdx; call send_packet_safe
    popq %r14; popq %r13; popq %r12; popq %rbx; ret

stream_loop_escaped:
    testq %r13, %r13; jz stream_done
    movzbl (%r14), %eax; cmpb $0xC0, %al; je escape_c0; cmpb $0xDB, %al; je escape_db
    movq %r14, %rsi; movq $1, %rdx; call send_packet_safe; jmp next_byte
escape_c0:
    leaq slip_esc(%rip), %rsi; movq $1, %rdx; call send_packet_safe
    leaq slip_esc_c0(%rip), %rsi; movq $1, %rdx; call send_packet_safe; jmp next_byte
escape_db:
    leaq slip_esc(%rip), %rsi; movq $1, %rdx; call send_packet_safe
    leaq slip_esc_db(%rip), %rsi; movq $1, %rdx; call send_packet_safe; jmp next_byte
next_byte:
    incq %r14; decq %r13; jmp stream_loop_escaped
stream_done:
    ret

do_sleep_100ms: movq $35, %rax; leaq sleep_100ms_ts(%rip), %rdi; xorq %rsi, %rsi; syscall; ret
do_sleep_200ms: movq $35, %rax; leaq sleep_200ms_ts(%rip), %rdi; xorq %rsi, %rsi; syscall; ret
