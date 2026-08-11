#include <stdint.h>

// USB-Serial-JTAG registers op de ESP32-C3
#define USB_SERIAL_JTAG_BASE 0x60043000
#define REG_USB_FIFO        (*(volatile uint32_t *)(USB_SERIAL_JTAG_BASE + 0x00)) // Data FIFO (Lezen / Schrijven)
#define REG_USB_ST          (*(volatile uint32_t *)(USB_SERIAL_JTAG_BASE + 0x04)) // Status / FIFO teller

// Watchdogs uitschakelen zodat de chip niet crasht in bare-metal
void disable_watchdogs(void) {
    *(volatile uint32_t *)0x6001F064 = 0x50D83AA1; // TG0 WDT protect
    *(volatile uint32_t *)0x6001F048 &= ~(1 << 31); // TG0 WDT config
    *(volatile uint32_t *)0x60020064 = 0x50D83AA1; // TG1 WDT protect
    *(volatile uint32_t *)0x60020048 &= ~(1 << 31); // TG1 WDT config
    *(volatile uint32_t *)0x600080A8 = 0x50D83AA1; // RTC WDT protect
    *(volatile uint32_t *)0x60008090 &= ~(1 << 31); // RTC WDT config
}

void _start(void) {
    disable_watchdogs();

    // LET OP: We raken register 0x6004301C (USB_SERIAL_JTAG_CONF0) 
    // NIET aan, zodat de USB-controller actief en verbonden blijft!

    while (1) {
        // Controleer het statusregister: 
        // De onderste bits (rx_fifo_cnt) geven aan hoeveel bytes er in de ontvangst-FIFO staan.
        uint32_t status = REG_USB_ST;
        
        if ((status & 0x0000000F) > 0) {
            // Lees de ontvangen byte uit de FIFO
            char c = (char)(REG_USB_FIFO & 0xFF);
            
            // ECHO: Schrijf dezelfde byte direct terug naar de FIFO
            REG_USB_FIFO = c;
        }
    }
}
