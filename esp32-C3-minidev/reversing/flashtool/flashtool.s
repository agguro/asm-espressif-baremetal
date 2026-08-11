.global _start

# =========================================================================
# BLOK 1: Read-Only Data (Konstanten, foutmeldingen en nanosleep struct)
# =========================================================================
.section .rodata
    default_dev:         .string "/dev/ttyUSB0"  
    
    msg_open_err:        .string "Fout: Kon poort niet openen.\n"
    len_open_err         = . - msg_open_err - 1

    msg_file_err:        .string "Fout: Kon binair bestand niet openen.\n"
    len_file_err         = . - msg_file_err - 1

    msg_open_ok:         .string "Poort succesvol geopend.\n"
    len_open_ok          = . - msg_open_ok - 1

    msg_tx_sync:         .string "TX (SYNC) : "
    len_tx_sync          = . - msg_tx_sync - 1

    msg_rx_sync:         .string "RX (SYNC) : "
    len_rx_sync          = . - msg_rx_sync - 1

    msg_tx_flash:        .string "Bezig met flashen...\n"
    len_tx_flash         = . - msg_tx_flash - 1

    msg_tx_end:          .string "TX (END)  : "
    len_tx_end           = . - msg_tx_end - 1

    msg_close:           .string "Poort succesvol gesloten.\n"
    len_close            = . - msg_close - 1

    newline:             .string "\n"
    hex_chars:           .string "0123456789ABCDEF"

    # Struct timespec voor sys_nanosleep (250 ms)
    .align 8
    ts_sec:  .quad 0
    ts_nsec: .quad 250000000

    # Het SLIP/ROM-bootloader SYNC pakket voor de ESP32-C3
    sync_packet:
        .byte 0xC0, 0x00, 0x08
        .2byte 36
        .4byte 0
        .byte 0x07, 0x07, 0x12, 0x20
        .fill 32, 1, 0x55
        .byte 0xC0
    sync_len = . - sync_packet

    # Het FLASH_END pakket (0x01 parameter zorgt voor reboot instructie)
    end_packet:
        .byte 0xC0
        .byte 0x00
        .byte 0x06
        .2byte 1
        .4byte 0
        .byte 0x01         # 0x01 = Reboot / Start de applicatie
        .byte 0xC0
    end_len = . - end_packet

# =========================================================================
# BLOK 2: BSS Sectie (Uninitialized variables in RAM)
# =========================================================================
.section .bss
    .lcomm fd, 8
    .lcomm file_fd, 8
    .lcomm file_size, 8
    .lcomm read_buf, 64         
    .lcomm hex_buf, 3           
    .lcomm termios, 64  
    .lcomm flash_payload, 1024      # Buffer voor 1 blok data
    .lcomm flash_packet, 1060       # 1 (0xC0) + 16 (header) + 1024 (data) + 2 (padding/0xC0) = 1043 bytes totaal

# =========================================================================
# BLOK 3: Programma Start & Command-Line Argument Parse
# =========================================================================
.section .text
_start:
    movq (%rsp), %rax           # Haal argc op
    cmpq $3, %rax               # Verwacht: ./flashtool <poort> <bestand.bin>
    jl check_single_arg

    movq 16(%rsp), %rdi         # argv[1] = seriële poort
    movq 24(%rsp), %r12         # argv[2] = binair bestand -> Bewaar veilig in %r12
    jmp open_port

check_single_arg:
    cmpq $2, %rax
    jl use_default_port
    leaq default_dev(%rip), %rdi
    movq 16(%rsp), %r12         # Bewaar in %r12
    jmp open_port

use_default_port:
    leaq default_dev(%rip), %rdi    # Gebruik default poort
    xorq %r12, %r12                 # Geen bestand

# =========================================================================
# BLOK 4: Seriële Poort & Bestand Openen
# =========================================================================
open_port:
    movq %rdi, %r8              
    movq $2, %rax               # Syscall: sys_open (poort)
    movq %r8, %rdi
    movq $2, %rsi               # O_RDWR
    movq $0, %rdx
    syscall
    
    cmpq $0, %rax
    js open_failed              
    movq %rax, fd(%rip)         

    testq %r12, %r12
    jz file_failed

    # Open het binaire firmware bestand (O_RDONLY)
    movq $2, %rax               # Syscall: sys_open (bestand)
    movq %r12, %rdi             # Gebruik de veilige pointer in %r12
    xorq %rsi, %rsi             # O_RDONLY
    xorq %rdx, %rdx
    syscall
    
    cmpq $0, %rax
    js file_failed
    movq %rax, file_fd(%rip)

    # Bepaal bestandsgrootte via lseek (SEEK_END)
    movq $8, %rax               # Syscall: sys_lseek
    movq file_fd(%rip), %rdi
    xorq %rsi, %rsi             # Offset 0
    movq $2, %rdx               # SEEK_END
    syscall
    movq %rax, file_size(%rip)

    # Zet file pointer terug naar begin (SEEK_SET)
    movq $8, %rax
    movq file_fd(%rip), %rdi
    xorq %rsi, %rsi
    xorq %rdx, %rdx
    syscall

    # Print melding: poort succesvol geopend
    movq $1, %rax               # Syscall: sys_write
    movq $1, %rdi               # Stdout
    leaq msg_open_ok(%rip), %rsi
    movq $len_open_ok, %rdx
    syscall

# =========================================================================
# BLOK 5: TTY Configuratie (Raw Mode & Timeout instellen via ioctl)
# =========================================================================
    movq $16, %rax              # Syscall: sys_ioctl
    movq fd(%rip), %rdi
    movq $0x5401, %rsi          
    leaq termios(%rip), %rdx
    syscall

    andl $0xFFFF0000, termios+0(%rip)    
    andl $0xFFFFFFFE, termios+4(%rip)    
    andl $0xFFFFFF70, termios+12(%rip)  
    andl $0xFFFFFFC0, termios+8(%rip)    
    orl  $0x00000030, termios+8(%rip)   # CS8 (8 databits)

    movb $0, termios + 17(%rip)        
    movb $1, termios + 18(%rip)        

    movq $16, %rax
    movq fd(%rip), %rdi
    movq $0x5402, %rsi          
    leaq termios(%rip), %rdx
    syscall

# =========================================================================
# BLOK 6: SYNC Handdruk Verzenden naar de ESP32-C3
# =========================================================================
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

# =========================================================================
# BLOK 7: Antwoord (RX) Lezen van de Bootloader
# =========================================================================
    movq $0, %rax               # Syscall: sys_read
    movq fd(%rip), %rdi
    leaq read_buf(%rip), %rsi
    movq $32, %rdx              
    syscall
    
    cmpq $0, %rax
    jle no_reply                

    movq %rax, %r15             

    movq $1, %rax
    movq $1, %rdi
    leaq msg_rx_sync(%rip), %rsi
    movq $len_rx_sync, %rdx
    syscall

    leaq read_buf(%rip), %rdi    
    movq %r15, %rsi             
    call print_hex_buffer

# =========================================================================
# BLOK 8: SPI_FLASH_BEGIN Commando Versturen (Commando 0x02)
# =========================================================================
    # Bereken totaal aantal blokken van 1024 bytes
    movq file_size(%rip), %rax
    addq $1023, %rax
    movq $1024, %rcx
    xorq %rdx, %rdx
    divq %rcx                   # %rax = totaal aantal blokken
    movq %rax, %r13             # Bewaar totaal aantal blokken in %r13

    # Bouw het SPI_FLASH_BEGIN SLIP pakket (commando 0x02)
    # Structuur: [0xC0] [Dir=0] [Cmd=0x02] [Size=16 bytes] [Checksum=0] [Payload (16 bytes)] [0xC0]
    # Payload:
    #   - total_size (4 bytes) : grootte van het bestand
    #   - num_blocks (4 bytes) : aantal blokken
    #   - block_size (4 bytes) : 1024
    #   - offset     (4 bytes) : 0x00000000 (of 0x10000 afhankelijk van de binary)

    subq $32, %rsp
    movb $0xC0, (%rsp)
    movb $0x00, 1(%rsp)
    movb $0x02, 2(%rsp)         # Commando 0x02 = SPI_FLASH_BEGIN
    movw $16,   3(%rsp)         # Data-lengte = 16 bytes
    movl $0,    5(%rsp)         # Checksum / argumenten = 0

    # Payload vullen:
    movq file_size(%rip), %rax
    movl %eax,   9(%rsp)        # Bestandsgrootte
    movl %r13d, 13(%rsp)        # Aantal blokken
    movl $1024, 17(%rsp)        # Blokgrootte (1024)
    movl $0x00000000, 21(%rsp)  # Flash startadres (0 voor merged image)
    movb $0xC0,  25(%rsp)       # SLIP end byte

    # Verstuur SPI_FLASH_BEGIN naar de poort
    movq $1, %rax
    movq fd(%rip), %rdi
    leaq (%rsp), %rsi
    movq $26, %rdx
    syscall
    addq $32, %rsp

    # Wacht even zodat de chip tijd heeft om de flash-sectoren fysiek te wissen (essentieel!)
    subq $16, %rsp
    movq $35, %rax
    leaq ts_sec(%rip), %rdi     # Hergebruik de 250ms nanosleep struct
    xorq %rsi, %rsi
    syscall
    addq $16, %rsp

    # Lees ACK / antwoord van de bootloader
    movq $0, %rax
    movq fd(%rip), %rdi
    leaq read_buf(%rip), %rsi
    movq $32, %rdx
    syscall
    
# =========================================================================
# BLOK 9: FLASH_DATA Blokken Verzenden (Commando 0x03)
# =========================================================================
    movq $1, %rax
    movq $1, %rdi
    leaq msg_tx_flash(%rip), %rsi
    movq $len_tx_flash, %rdx
    syscall

    xorq %r14, %r14             # Huidige blok index (start bij 0)

flash_loop:
    cmpq %r13, %r14
    jge flash_done              # Als index == totaal aantal blokken, klaar

    # Lees tot 1024 bytes uit het bestand naar flash_payload buffer
    movq $0, %rax               # sys_read
    movq file_fd(%rip), %rdi
    leaq flash_payload(%rip), %rsi
    movq $1024, %rdx
    syscall
    movq %rax, %r12             # Aantal daadwerkelijk gelezen bytes

    testq %r12, %r12
    jle flash_done

    # Bouw het COMPLETE SLIP pakket in flash_packet buffer:
    # [0xC0] [16-byte header] [Payload (%r12 bytes)] [0xC0]
    
    leaq flash_packet(%rip), %r8

    # 1. Start SLIP byte
    movb $0xc0, (%r8)

    # 2. Header (16 bytes opbouwen vanaf offset 1)
    movb $0x00, 1(%r8)          # Direction = 0
    movb $0x03, 2(%r8)          # Cmd = 0x03 (FLASH_DATA)
    
    # Size = payload lengte (%r12) + 16 bytes header argumenten
    movq %r12, %rax
    addq $16, %rax
    movw %ax, 3(%r8)            # Size (2 bytes)

    movl $0, 5(%r8)             # Checksum / argumenten (4 bytes)
    movl %r14d, 9(%r8)          # Sequence / bloknummer (4 bytes)
    movl $0, 13(%r8)            # Extra padding velden (4 bytes)

    # 3. Kopieer de payload data naar offset 17 van de buffer
    leaq 17(%r8), %rdi          # Dest: begin van payload in packet
    leaq flash_payload(%rip), %rsi # Source: ingelezen data
    movq %r12, %rcx             # Aantal bytes
    cld
    rep movsb                   # Kopieer blok

    # 4. SLIP end byte 0xC0 direct na de payload plaatsen
    movq %r12, %rax
    addq $17, %rax              # Index van eindbyte
    movb $0xC0, (%r8, %rax)     # Schrijf 0xC0

    # Bereken totale pakketgrootte voor de write syscall: 1 (start) + 16 (header) + %r12 (payload) + 1 (end) = %r12 + 18
    addq $18, %rax
    movq %rax, %r9              # Bewaar totale pakketlengte in %r9

    # 5. Verstuur het VOLLEDIGE pakket in ÉÉN enkel write commando naar de poort!
    movq $1, %rax               # sys_write
    movq fd(%rip), %rdi         # File descriptor van seriële poort
    movq %r8, %rsi              # Pointer naar flash_packet buffer
    movq %r9, %rdx              # Totale lengte
    syscall

    # 6. Wacht op ACK van de bootloader voor dit blok
    movq $0, %rax               # sys_read
    movq fd(%rip), %rdi
    leaq read_buf(%rip), %rsi
    movq $32, %rdx
    syscall

    incq %r14                   # Verhoog blokindex
    jmp flash_loop

flash_done:

# =========================================================================
# BLOK 10: Flash Afsluiten (FLASH_END = 0x04) & Reboot
# =========================================================================
exit_clean:
    movq $1, %rax
    movq $1, %rdi
    leaq msg_tx_end(%rip), %rsi
    movq $len_tx_end, %rdx
    syscall

    # Bouw correct FLASH_END SLIP pakket (Commando 0x04, argument = 0 om flash-modus te verlaten)
    # Formaat: [0xC0] [Dir=0] [Cmd=0x04] [Size=4 bytes] [Arg=0 (stay=0)] [0xC0]
    subq $16, %rsp
    movb $0xC0, (%rsp)
    movb $0x00, 1(%rsp)
    movb $0x04, 2(%rsp)         # Commando 0x04 = FLASH_END
    movw $4,    3(%rsp)         # Size = 4 bytes
    movl $0,    5(%rsp)         # Argument: 0 = verlaat flash mode / klaar voor run
    movb $0xC0, 9(%rsp)

    # Verstuur FLASH_END naar de poort
    movq $1, %rax
    movq fd(%rip), %rdi
    leaq (%rsp), %rsi
    movq $10, %rdx
    syscall
    addq $16, %rsp

    # Lees ACK van bootloader
    movq $0, %rax
    movq fd(%rip), %rdi
    leaq read_buf(%rip), %rsi
    movq $16, %rdx
    syscall
    

# =========================================================================
# BLOK 11: Directe Hardware Reset Sequencer (Zonder TIOCMGET afhankelijkheid)
# =========================================================================
    subq $16, %rsp

    # Zet direct DTR laag (0) en RTS hoog (1) -> Houdt EN-pin laag (Reset actief)
    movq $0x004, (%rsp)         # Alleen RTS aan (RTS=1, DTR=0)
    movq $16, %rax
    movq fd(%rip), %rdi
    movq $0x5418, %rsi          # TIOCMSET
    leaq (%rsp), %rdx
    syscall

    # Wacht 250ms via sys_nanosleep
    movq $35, %rax
    leaq ts_sec(%rip), %rdi     
    xorq %rsi, %rsi
    syscall

    # Laat los -> DTR hoog (1) en RTS laag (0) -> Boot de applicatie
    movq $0x002, (%rsp)         # Alleen DTR aan (RTS=0, DTR=1)
    movq $16, %rax
    movq fd(%rip), %rdi
    movq $0x5418, %rsi          # TIOCMSET
    leaq (%rsp), %rdx
    syscall

    addq $16, %rsp

# =========================================================================
# BLOK 12: Foutafhandeling
# =========================================================================
open_failed:
    movq $1, %rax
    movq $1, %rdi
    leaq msg_open_err(%rip), %rsi
    movq $len_open_err, %rdx
    syscall
    movq $1, %r12
    jmp exit

file_failed:
    movq $1, %rax
    movq $1, %rdi
    leaq msg_file_err(%rip), %rsi
    movq $len_file_err, %rdx
    syscall
    movq $1, %r12
    jmp exit

no_reply:
    movq $2, %r12
    jmp close_and_exit

# =========================================================================
# BLOK 13: Opruimen en Afsluiten
# =========================================================================
close_and_exit:
    movq $3, %rax               # sys_close (poort)
    movq fd(%rip), %rdi
    syscall

    movq file_fd(%rip), %rax
    testq %rax, %rax
    jz finish_exit
    movq $3, %rax               # sys_close (bestand)
    movq file_fd(%rip), %rdi
    syscall

finish_exit:
    movq %r12, %rdi
exit:
    movq $60, %rax
    syscall

# =========================================================================
# BLOK 14: Subroutine - Print Hex
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
