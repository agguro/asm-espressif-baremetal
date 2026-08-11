    .global _start

    .equ HDR_SIZE, 24
    .equ SEG_HDR_SIZE, 8

    .data
fd:     .long 0
size:   .quad 0

    .text
_start:
    # argv[1] → bestandsnaam
    mov 16(%rsp), %rdi
    test %rdi, %rdi
    jz exit

    # open(filename, O_RDWR)
    mov $2, %rax          # sys_open
    mov $2, %rsi          # O_RDWR
    xor %rdx, %rdx
    syscall
    cmp $0, %rax
    js exit
    mov %eax, fd(%rip)

    # lseek(fd, 0, SEEK_END)
    mov $8, %rax          # sys_lseek
    mov fd(%rip), %rdi
    xor %rsi, %rsi
    mov $2, %rdx          # SEEK_END
    syscall
    cmp $0, %rax
    js close_exit
    mov %rax, size(%rip)

    # mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0)
    mov $9, %rax          # sys_mmap
    xor %rdi, %rdi        # addr = NULL
    mov size(%rip), %rsi  # length
    mov $3, %rdx          # PROT_READ|PROT_WRITE
    mov $1, %r10          # MAP_SHARED
    mov fd(%rip), %r8     # fd
    xor %r9, %r9          # offset = 0
    syscall
    cmp $0, %rax
    js close_exit
    mov %rax, %rbx        # base pointer

    # rcx = data_start = base + HDR_SIZE + SEG_HDR_SIZE
    mov %rbx, %rcx
    add $(HDR_SIZE + SEG_HDR_SIZE), %rcx

    # rdx = checksum_ptr = base + size - 1
    mov size(%rip), %rdx
    dec %rdx
    add %rbx, %rdx

    # r8 = sum
    xor %r8, %r8

sum_loop:
    cmp %rcx, %rdx
    jge write_checksum

    movzbq (%rcx), %rax
    add %rax, %r8
    inc %rcx
    jmp sum_loop

write_checksum:
    mov %r8d, %eax
    and $0xFF, %eax
    mov %al, (%rdx)

    # msync(base, size, MS_SYNC)
    mov $26, %rax         # sys_msync
    mov %rbx, %rdi
    mov size(%rip), %rsi
    mov $4, %rdx          # MS_SYNC
    syscall

close_exit:
    mov $3, %rax          # sys_close
    mov fd(%rip), %rdi
    syscall

exit:
    mov $60, %rax         # sys_exit
    xor %rdi, %rdi
    syscall

