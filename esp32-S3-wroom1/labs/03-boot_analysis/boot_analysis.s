.global _start

.section .rodata
    dev_path:      .string "/dev/ttyACM0"
    
    msg_open_ok:   .string "Poort succesvol geopend door Ouder.\n"
    len_open_ok  = . - msg_open_ok - 1

    msg_tx_sync:   .string "TX (SYNC)  : "
    len_tx_sync  = . - msg_tx_sync - 1

    msg_rx_sync:   .string "RX (SYNC)  : "
    len_rx_sync  = . - msg_rx_sync - 1

    msg_tx_id:     .string "TX (CHIPID): "
    len_tx_id    = . - msg_tx_id - 1

    msg_rx_id:     .string "RX (CHIPID): "
    len_rx_id    = . - msg_rx_id - 1

    msg_fork:      .string "\n[+] Binaire handdruk compleet. Ouder fork()t Kind voor ASCII-monitoring...\n"
    len_fork     = . - msg_fork - 1

    msg_child_st:  .string "[*] Kind-proces actief. Slikt nu alle chip-output door naar stdout...\n"
    len_child_st = . - msg_child_st - 1

    msg_close:     .string "\n[+] Ouder heeft exit van Kind opgevangen via wait4. Poort gesloten.\n"
    len_close    = . - msg_close - 1

    newline:       .string "\n"
    hex_chars:     .string "0123456789ABCDEF"

    # Het 46-byte binaire SYNC pakket
    sync_packet:
        .byte 0xC0, 0x00, 0x08
        .2byte 36
        .4byte 0
        .byte 0x07, 0x07, 0x12, 0x20
        .fill 32, 1, 0x55
        .byte 0xC0
    sync_len = . - sync_packet

    # Het 14-byte READ_REG pakket voor eFuse adres 0x60007044
    chipid_packet:
        .byte 0xC0, 0x00, 0x0A
        .2byte 4
        .4byte 0
        .4byte 0x60007044           
        .byte 0xC0
    chipid_len = . - chipid_packet

.section .bss
    .lcomm fd, 8
    .lcomm read_buf, 64     
    .lcomm single_byte, 1   
    .lcomm hex_buf, 3       
    .lcomm termios, 64 

.section .text
_start:
    # 1. Ouder opent /dev/ttyACM0 (O_RDWR)
    movq $2, %rax              
    leaq dev_path(%rip), %rdi
    movq $2, %rsi               
    movq $0, %rdx
    syscall
    
    cmpq $0, %rax
    js open_failed          
    movq %rax, fd(%rip)     

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

    andl $0xFFFF0000, termios+0(%rip)  
    andl $0xFFFFFFFE, termios+4(%rip)  
    andl $0xFFFFFF70, termios+12(%rip) 
    andl $0xFFFFFFC0, termios+8(%rip)  
    orl  $0x00000030, termios+8(%rip)  

    # We zetten de poort in TIMEOUT stand (VTIME=1, VMIN=0) voor de ouder
    # Mocht de handmatige bootloader-dans nog niet gedaan zijn, hangt de ouder niet vast.
    movb $1, termios+17+5(%rip) # VTIME = 1 (100ms timeout)
    movb $0, termios+17+6(%rip) # VMIN = 0

    movq $16, %rax
    movq fd(%rip), %rdi
    movq $0x5402, %rsi         
    leaq termios(%rip), %rdx
    syscall

    # 3. Verzend binaire SYNC (Ouder heeft het alleenrecht)
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

    # 5. Verzend READ_REG voor Chip ID
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

    # 6. Filter en vang 0x0A Chip ID respons
read_id_retry:
    movq $0, %rax              
    movq fd(%rip), %rdi
    leaq read_buf(%rip), %rsi
    movq $14, %rdx              
    syscall
    
    cmpq $0, %rax
    jle no_reply            

    movzbq read_buf+2(%rip), %rax
    cmpq $0x0A, %rax
    jne read_id_retry          

    movq $1, %rax
    movq $1, %rdi
    leaq msg_rx_id(%rip), %rsi
    movq $len_rx_id, %rdx
    syscall

    leaq read_buf(%rip), %rdi   
    movq $14, %rsi              
    call print_hex_buffer

    # =========================================================================
    # DE WEBSERVER SWITCH: Slinger de monitor aan via fork()
    # =========================================================================
    movq $1, %rax
    movq $1, %rdi
    leaq msg_fork(%rip), %rsi
    movq $len_fork, %rdx
    syscall

    movq $57, %rax              # sys_fork
    syscall

    cmpq $0, %rax
    js fork_failed
    je child_monitor_process    # Kind springt direct naar de ASCII monitor

    # -------------------------------------------------------------------------
    # OUDER-PROCES: De server-master die waakt over het kind
    # -------------------------------------------------------------------------
    # We voeren sys_wait4 (Syscall 61) uit om te wachten tot het kind sterft
    movq $61, %rax              # sys_wait4
    movq $-1, %rdi              # Wacht op elke child PID
    movq $0, %rsi               # Geen status-struct nodig
    movq $0, %rdx               # Geen opties
    movq $0, %r10               # Geen rusage nodig
    syscall

    # Kind is gestopt, ouder sluit de tent netjes af
    movq $0, %r12
    jmp close_and_exit

    # -------------------------------------------------------------------------
    # KIND-PROCES: De dedicated ASCII / Log Toeschouwer
    # -------------------------------------------------------------------------
child_monitor_process:
    # Print startbericht van het kind
    movq $1, %rax
    movq $1, %rdi
    leaq msg_child_st(%rip), %rsi
    movq $len_child_st, %rdx
    syscall

    # Schakel de termios van het kind over naar VOLLEDIG BLOCKING (VMIN=1, VTIME=0)
    # Zo blijft het kind oneindig lang luisteren naar wat de chip doet!
    movq $16, %rax
    movq fd(%rip), %rdi
    movq $0x5401, %rsi         
    leaq termios(%rip), %rdx
    syscall
    movb $0, termios+17+5(%rip) # VTIME = 0
    movb $1, termios+17+6(%rip) # VMIN = 1
    movq $16, %rax
    movq fd(%rip), %rdi
    movq $0x5402, %rsi         
    leaq termios(%rip), %rdx
    syscall

child_loop:
    movq $0, %rax              # sys_read
    movq fd(%rip), %rdi
    leaq single_byte(%rip), %rsi
    movq $1, %rdx              
    syscall

    cmpq $1, %rax
    jne child_exit             

    # Schrijf elke binnenkomende byte direct rauw naar stdout
    movq $1, %rax
    movq $1, %rdi
    leaq single_byte(%rip), %rsi
    movq $1, %rdx
    syscall
    jmp child_loop

child_exit:
    movq $60, %rax             # sys_exit voor het kind
    movq $0, %rdi
    syscall

# -------------------------------------------------------------------------
# AFSLUITING & FOUTEN
# -------------------------------------------------------------------------
open_failed:
    movq $60, %rax
    movq $1, %rdi
    syscall

fork_failed:
    movq $60, %rax
    movq $2, %rdi
    syscall

no_reply:
    movq $3, %r12
    # Indien de ouder geen respons kreeg, sluiten we alsnog af

close_and_exit:
    movq $3, %rax              # sys_close
    movq fd(%rip), %rdi
    syscall

    movq $1, %rax              
    movq $1, %rdi              
    leaq msg_close(%rip), %rsi
    movq $len_close, %rdx
    syscall

    movq %r12, %rdi            
    movq $60, %rax             # sys_exit
    syscall

# =========================================================================
# SUBROUTINE: print_hex_buffer
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

