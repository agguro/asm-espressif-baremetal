# ota_states.s - GNU Assembler Include voor ESP-IDF OTA States
# Te importeren via: .include "ota_states.s"

.equ ESP_OTA_IMG_NEW,            0x00
.equ ESP_OTA_IMG_PENDING_VERIFY, 0x01
.equ ESP_OTA_IMG_VALID,          0x02
.equ ESP_OTA_IMG_INVALID,        0x03
.equ ESP_OTA_IMG_UNDEFINED,      0xFFFFFFFF
