# riscv32-esp-elf-as -o interrupt_table.o interrupt_table.s

.section .text
.align 4
.global _vector_table

_vector_table:
    j _vector_0_reserved          # 0: Reserved / Exception / Panic
    j _vector_1_wifi_mac          # 1: WiFi MAC Interrupt
    j _vector_2_wifi_bb           # 2: WiFi Baseband Interrupt
    j _vector_3_bt_mac            # 3: Bluetooth MAC Interrupt
    j _vector_4_bt_bb             # 4: Bluetooth Baseband Interrupt
    j _vector_5_lp_timer          # 5: Ultra Low Power (ULP) / LP Timer
    j _vector_6_pmU               # 6: Power Management Unit
    j _vector_7_systimer          # 7: System Timer Target 0/1
    j _vector_8_sec_crypto        # 8: Security / Crypto Accelerator
    j _vector_9_dma               # 9: SPI/DMA Interrupt
    j _vector_10_uart0            # 10: UART 0 Interrupt
    j _vector_11_uart1            # 11: UART 1 Interrupt
    j _vector_12_ledc             # 12: LED PWM Controller (LEDC)
    j _vector_13_efuse            # 13: eFuse Controller
    j _vector_14_twai             # 14: TWAI (CAN) Controller
    j _vector_15_usb_serial_jtag  # 15: USB Serial/JTAG Controller
    j _vector_16_rtc_core         # 16: RTC Core Interrupt
    j _vector_17_rmt              # 17: Remote Control Peripheral (RMT)
    j _vector_18_i2c0             # 18: I2C Controller 0
    j _vector_19_i2c1             # 19: I2C Controller 1
    j _vector_20_spi2             # 20: SPI 2 (GPSPI2)
    j _vector_21_spi3             # 21: SPI 3 (GPSPI3)
    j _vector_22_aes              # 22: AES Accelerator
    j _vector_23_sha              # 23: SHA Accelerator
    j _vector_24_rsa              # 24: RSA Accelerator
    j _vector_25_ecc              # 25: ECC Accelerator
    j _vector_26_tray             # 26: Tray / Random Number Generator
    j _vector_27_gpio             # 27: GPIO Interrupt (Multi-pin)
    j _vector_28_gdma             # 28: General Direct Memory Access (GDMA)
    j _vector_29_cpu_intr_29      # 29: Software / CPU Interrupt 29
    j _vector_30_cpu_intr_30      # 30: Software / CPU Interrupt 30
    j _vector_31_cpu_intr_31      # 31: Software / CPU Interrupt 31
