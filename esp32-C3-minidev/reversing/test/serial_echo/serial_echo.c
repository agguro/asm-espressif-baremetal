/* =====================================================================
 * Minimal Bare-Metal C Serial Echo for ESP32-C3 (Freestanding)
 * Compiles without libc/runtime ballast.
 * ===================================================================== */

typedef unsigned int uint32_t;

// Hardware registers voor UART0 (Direct memory-mapped)
#define UART_FIFO   ((volatile uint32_t*)0x60000000)
#define UART_STATUS ((volatile uint32_t*)0x6000001C)

void _start(void) {
    // Hoofdloop voor seriële echo
    while (1) {
        // 1. Polling: Wacht tot rxfifo_cnt ([23:16]) groter is dan 0
        while (((*UART_STATUS >> 16) & 0xFF) == 0) {
            // Wacht tot er data binnenkomt
        }

        // 2. Lees het 32-bits woord uit de UART0 RX FIFO
        uint32_t data = *UART_FIFO;

        // 3. Schrijf het teken direct terug naar de TX FIFO (Echo)
        *UART_FIFO = data;
    }
}
