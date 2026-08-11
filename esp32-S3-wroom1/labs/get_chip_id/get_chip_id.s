.global _start

.section .rodata
    dev_path:      .string "/dev/ttyACM0"
    
    msg_open_err:  .string "Fout: Kon poort niet openen.\n"
    len_open_err = . - msg_open_err - 1

    msg_open_ok:   .string "Poort succesvol geopend.\n"
    len_open_ok  = . - msg_open_ok - 1

    msg_boot_txt:  .string "Chip Boot-tekst:\n"
    len_boot_txt = . - msg_boot_txt - 1

    msg_tx_sync:   .string "TX (SYNC)  : "
    len_tx_sync  = . - msg_tx_sync - 1

    msg_rx_sync:   .string "RX (SYNC)  : "
    len_rx_sync  = . - msg_rx_sync - 1

    msg_tx_id:     .string "TX (CHIPID): "
    len_tx_id    = . - msg_tx_id - 1

    msg_rx_id:     .string "RX (CHIPID): "
    len_rx_id    = . - msg_rx_id - 1

    msg_tx_stop:   .string "TX (STOP)  : "
    len_tx_stop  = . - msg_tx_stop - 1

    msg_close:     .string "Poort succesvol gesloten. Programma stopt.\n"
    len_close    = . - msg_close - 1

    newline:       .string "\n"
    hex_chars:     .string "0123456789ABCDEF"

    # Het 46-byte SYNC pakket (Opcode 0x08)
    sync_packet:
        .byte 0xC0, 0x00, 0x08
        .2byte 36
        .4byte 0
        .byte 0x07, 0x07, 0x12, 0x20
        .fill 32, 1, 0x55
        .byte 0xC0
    sync_len = . - sync_packet

    # Het 14-byte READ_REG pakket (Opcode 0x0A) om eFuse adres 0x60007044 te lezen
    chipid_packet:
        .byte 0xC0, 0x00, 0x0A
        .2byte 4
        .4byte 0
        .4byte 0x60007044           # Target Adres (Little-endian: 44 70 00 60)
        .byte 0xC0
    chipid_len = . - chipid_packet

    # Het 11-byte FLASH_END pakket (Opcode 0x06) om af te sluiten
    end_packet:
        .byte 0xC0, 0x00, 0x06
        .2byte 1
        .4byte 0
        .byte 0x00                  
        .byte 0xC0
    end_len = . - end_packet

.section .bss
    .lcomm fd, 8
    .lcomm read_buf, 64     # Ruime buffer voor ASCII of binair
    .lcomm hex_buf, 3       
    .lcomm termios, 64 

.section .text
_start:
    # 1. Open /dev/ttyACM0 (Blocking Mode, O_RDWR)
    movq $2, %rax              
    leaq dev_path(%rip), %rdi
    movq $2, %rsi               
    movq $0, %rdx
    syscall
    
    cmpq $0, %rax
    js open_failed          
    movq %rax, fd(%rip)     

    # Print succesvol geopend
    movq $1, %rax              
    movq $1, %rdi              
    leaq msg_open_ok(%rip), %rsi
    movq $len_open_ok, %rdx
    syscall

    # 2. Configureer tty naar RAW MODE via ioctl
    movq $16, %rax
    movq fd(%rip), %rdi
    movq $0x5401, %rsi         
    leaq termios(%rip), %rdx
    syscall

    andl $0xFFFF0000, termios+0(%rip)  # c_iflag
    andl $0xFFFFFFFE, termios+4(%rip)  # c_oflag
    andl $0xFFFFFF70, termios+12(%rip) # c_lflag
    andl $0xFFFFFFC0, termios+8(%rip)  # c_cflag
    orl  $0x00000030, termios+8(%rip)  # CS8

    # TIME-OUT INSTELLEN (c_cc struct start op offset 17)
    # c_cc[VTIME] = 1 -> Wacht maximaal 100ms op inkomende bytes
    movb $1, termios+17+5(%rip)
    # c_cc[VMIN]  = 0 -> Als de 100ms om is, geef direct terug wat er is
    movb $0, termios+17+6(%rip)

    movq $16, %rax
    movq fd(%rip), %rdi
    movq $0x5402, %rsi         
    leaq termios(%rip), %rdx
    syscall

    # 2.5 Consumeer de volledige ASCII boot-tekst tot er radiostilte valt
    movq $1, %rax
    movq $1, %rdi
    leaq msg_boot_txt(%rip), %rsi
    movq $len_boot_txt, %rdx
    syscall

consume_boot_loop:
    movq $0, %rax              # sys_read
    movq fd(%rip), %rdi
    leaq read_buf(%rip), %rsi
    movq $64, %rdx              
    syscall

    cmpq $0, %rax
    jle boot_done              # Radiostilte? Dan is de chip klaar voor binair!
    movq %rax, %r12            

    # Schrijf de opgevangen ASCII-bytes direct naar stdout
    movq $1, %rax
    movq $1, %rdi
    leaq read_buf(%rip), %rsi
    movq %r12, %rdx
    syscall

    jmp consume_boot_loop      

boot_done:
    movq $1, %rax
    movq $1, %rdi
    leaq newline(%rip), %rsi
    movq $1, %rdx
    syscall

    # 3. Verzend SYNC handdruk
    movq $1, %rax
    movq $1, %rdi
    leaq msg_tx_sync(%rip), %rsi
    movq $len_tx_sync, %rdx
    syscall

    leaq sync_packet(%rip), %rdi 
    movq $sync_len, %rsi         
    call print_hex_buffer

    movq $1, %rax
    movq fd(%rip), %rdi
    leaq sync_packet(%rip), %rsi
    movq $sync_len, %rdx
    syscall

    # 4. Consumeer antwoord op SYNC (14 bytes)
    movq $0, %rax
    movq fd(%rip), %rdi
    leaq read_buf(%rip), %rsi
    movq $14, %rdx              
    syscall
    
    cmpq $0, %rax
    jle no_reply            

    movq $1, %rax
    movq $1, %rdi
    leaq msg_rx_sync(%rip), %rsi
    movq $len_rx_sync, %rdx
    syscall

    leaq read_buf(%rip), %rdi   
    movq $14, %rsi              
    call print_hex_buffer

    # 5. Verzend DIRECT het READ_REG commando voor de Chip ID
    movq $1, %rax
    movq $1, %rdi
    leaq msg_tx_id(%rip), %rsi
    movq $len_tx_id, %rdx
    syscall

    leaq chipid_packet(%rip), %rdi
    movq $chipid_len, %rsi
    call print_hex_buffer

    movq $1, %rax
    movq fd(%rip), %rdi
    leaq chipid_packet(%rip), %rsi
    movq $chipid_len, %rdx
    syscall

    # 6. LEZEN EN FILTEREN: Zoek gericht naar het antwoord op READ_REG (Opcode 0x0A)
read_id_retry:
    movq $0, %rax              # sys_read
    movq fd(%rip), %rdi
    leaq read_buf(%rip), %rsi
    movq $14, %rdx              
    syscall
    
    cmpq $0, %rax
    jle no_reply            

    # Check de opcode op byte index 2 van het ontvangen pakket
    movzbq read_buf+2(%rip), %rax
    cmpq $0x0A, %rax
    jne read_id_retry          # Is het een 0x08 (SYNC)? Weggooien en opnieuw lezen!

    # Bingo! We hebben het 0x0A antwoord te pakken.
    movq $1, %rax
    movq $1, %rdi
    leaq msg_rx_id(%rip), %rsi
    movq $len_rx_id, %rdx
    syscall

    leaq read_buf(%rip), %rdi   
    movq $14, %rsi              
    call print_hex_buffer

exit_clean:
    # 7. Stuur tenslotte het FLASH_END commando om de chip af te sluiten
    movq $1, %rax
    movq $1, %rdi
    leaq msg_tx_stop(%rip), %rsi
    movq $len_tx_stop, %rdx
    syscall

    leaq end_packet(%rip), %rdi
    movq $end_len, %rsi
    call print_hex_buffer

    movq $1, %rax
    movq fd(%rip), %rdi
    leaq end_packet(%rip), %rsi
    movq $end_len, %rdx
    syscall

    movq $0, %r12              # Exit code 0
    jmp close_and_exit

open_failed:
    movq $1, %rax
    movq $1, %rdi
    leaq msg_open_err(%rip), %rsi
    movq $len_open_err, %rdx
    syscall
    movq $1, %r12              
    jmp exit                   

no_reply:
    movq $2, %r12              
    jmp close_and_exit

close_and_exit:
    movq $3, %rax              # sys_close
    movq fd(%rip), %rdi
    syscall

    movq $1, %rax              # sys_write
    movq $1, %rdi              # stdout
    leaq msg_close(%rip), %rsi
    movq $len_close, %rdx
    syscall

    movq %r12, %rdi            

exit:
    movq $60, %rax             # sys_exit
    syscall

# =========================================================================
# SUBROUTINE: print_hex_buffer (%rdi = pointer, %rsi = lengte)
# =========================================================================
print_hex_buffer:
    pushq %rbx
    pushq %r12
    pushq %r13
    pushq %r14
    movq %rdi, %rbx            
    movq %rsi, %r12            
    xorq %r13, %r13            
    leaq hex_chars(%rip), %r14 
1:
    cmpq %r12, %r13
    je 2f                      
    movzbq (%rbx, %r13), %rax  
    
    movq %rax, %rcx
    shrq $4, %rcx              
    movb (%r14, %rcx), %dl     
    movb %dl, hex_buf+0(%rip)  
    
    movq %rax, %rcx
    andq $0x0F, %rcx           
    movb (%r14, %rcx), %dl     
    movb %dl, hex_buf+1(%rip)  
    
    movb $32, hex_buf+2(%rip)  

    movq $1, %rax
    movq $1, %rdi
    leaq hex_buf(%rip), %rsi
    movq $3, %rdx
    syscall
    
    incq %r13                  
    jmp 1b
2:
    movq $1, %rax
    movq $1, %rdi
    leaq newline(%rip), %rsi
    movq $1, %rdx
    syscall
    
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    ret

.size _start, . - _start
.section .note.GNU-stack,"",@progbits

