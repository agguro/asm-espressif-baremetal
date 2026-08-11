.section .text
.align 4
.global _vector_table

_vector_table:
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler
    j _interrupt_handler

