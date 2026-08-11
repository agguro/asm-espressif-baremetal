.section .text
.align 2
.global _panic_handler

_panic_handler:
    wfi
    j _panic_handler

