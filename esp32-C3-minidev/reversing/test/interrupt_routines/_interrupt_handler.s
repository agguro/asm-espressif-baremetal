.section .text
.align 2
.global _interrupt_handler
_interrupt_handler:
    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mtval
    # later we can add debugging info etc.
    mret
