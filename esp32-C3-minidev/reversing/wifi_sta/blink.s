; =====================================================================
; Bare-metal Assembly Blink for ATmega2560
; NO VECTORS, NO STACK, ONE DELAY INSTANCE, HARDWARE TOGGLE
; Target Pin: Port B, Pin 7 (Onboard LED "L")
; =====================================================================

.section .text
.global _start

_start:
    ; 1. Configure Port B Pin 7 (PB7) as Output
    sbi 0x04, 7             ; DDRB |= (1 << 7)

loop:
    ; 2. Hardware Toggle Trick: Writing a 1 to PINB7 flips PORTB7
    ; PINB is at I/O address 0x03
    sbi 0x03, 7             ; Toggle PB7 state (ON -> OFF or OFF -> ON)

    ; 3. Shared Inline Delay ~1 second
    ldi r26, 82
delay_outer:
    ldi r25, 255
delay_middle:
    ldi r24, 255
delay_inner:
    dec r24
    brne delay_inner
    dec r25
    brne delay_middle
    dec r26
    brne delay_outer

    rjmp loop               ; Infinite Loop back to toggle
