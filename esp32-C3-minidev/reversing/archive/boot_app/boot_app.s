# boot_app0.s - Volledig geoptimaliseerde boot_app0 structuur in gas
# ABI- en uitlijningsproof (.align 4)

.section .rodata
.align 4

# Importeer de OTA-statussen
.include "ota_states.s"

.global boot_app0_bin
.global boot_app0_bin_end

boot_app0_bin:
    # --- Veld 1: ota_seq (32-bits volgnummer) ---
    # Behouden met individuele byte-labels voor directe adressering indien nodig
    byte0_OTA_seq_lsb:
    byte1_OTA_seq:
    byte2_OTA_seq:
    byte3_OTA_seq_msb:
        .4byte ESP_OTA_IMG_PENDING_VERIFY

    # --- Veld 2: ota_state (32-bits status) ---
    # Maakt gebruik van de geïmporteerde constante uit ota_states.s
    byte4_OTA_state:
        .4byte ESP_OTA_IMG_UNDEFINED

    # --- Veld 3: Rest van de header (tot 32 bytes totaal) ---
    .space (32 - (. - boot_app0_bin)), 0xFF

    # --- Veld 4: Padding tot exact 8192 bytes (0x2000) ---
    .space (8192 - (. - boot_app0_bin)), 0xFF

boot_app0_bin_end:
