#include <Arduino.h>
#include <U8g2lib.h>
#include <Wire.h>

// Scherm dimensies voor de ESP32-C3 mini kit
#define SCHERM_BREEDTE 72
#define SCHERM_HOOGTE  40
#define MATRIX_BREEDTE (SCHERM_BREEDTE / 8) // 9 bytes breed

// Scherm initialisatie (GPIO 5 = SDA, GPIO 6 = SCL)
U8G2_SSD1306_72X40_ER_F_HW_I2C u8g2(U8G2_R0, /* reset=*/ U8X8_PIN_NONE, /* clock=*/ 6, /* data=*/ 5);

#define RODE_LED_PIN 8

// De dynamische pixelbuffer in het RAM. 
// Deze array kun je later via functies of scripts dynamisch vullen met andere patronen!
uint8_t frameBuffer[MATRIX_BREEDTE * SCHERM_HOOGTE];

// Functie om alle pixels in onze eigen array te wissen (zwart te maken)
void wisMatrix() {
  memset(frameBuffer, 0, sizeof(frameBuffer));
}

// Functie om een specifieke pixel aan (1) of uit (0) te zetten in de array
void zetPixel(int x, int y, bool aan) {
  if (x >= 0 && x < SCHERM_BREEDTE && y >= 0 && y < SCHERM_HOOGTE) {
    int byteIndex = y * MATRIX_BREEDTE + (x / 8);
    int bitIndex = x % 8;
    
    if (aan) {
      frameBuffer[byteIndex] |= (1 << bitIndex);  // Bit op 1 zetten
    } else {
      frameBuffer[byteIndex] &= ~(1 << bitIndex); // Bit op 0 zetten
    }
  }
}

// Functie om een gevulde cirkel in de array te tekenen
void tekenCirkel(int cx, int cy, int straal) {
  for (int y = -straal; y <= straal; y++) {
    for (int x = -straal; x <= straal; x++) {
      if (x*x + y*y <= straal*straal) {
        zetPixel(cx + x, cy + y, true);
      }
    }
  }
}

// Functie om een gevulde driehoek in de array te tekenen (vlakke bodem/top variant)
void tekenDriehoek() {
  // Specifieke hardcoded driehoek-vulling voor de punt van het hart
  for (int y = 17; y <= 36; y++) {
    // Lineaire interpolatie voor de schuine zijden van de punt
    int xStart = 21 + (y - 17) * 14 / 19;
    int xEind  = 49 - (y - 17) * 14 / 19;
    for (int x = xStart; x <= xEind; x++) {
      zetPixel(x, y, true);
    }
  }
}

// Bouw de uiteindelijke afbeelding op in de array
void genereerAfbeelding() {
  wisMatrix();

  // 1. Teken een maximaal kader (buitenste randen van de matrix)
  for (int x = 0; x < SCHERM_BREEDTE; x++) {
    zetPixel(x, 0, true);                   // Bovenrand
    zetPixel(x, SCHERM_HOOGTE - 1, true);   // Onderrand
  }
  for (int y = 0; y < SCHERM_HOOGTE; y++) {
    zetPixel(0, y, true);                   // Linkerrand
    zetPixel(SCHERM_BREEDTE - 1, y, true);  // Rechterrand
  }

  // 2. Teken het hartje binnen het kader in de array
  tekenCirkel(28, 14, 7); // Linkerboog
  tekenCirkel(42, 14, 7); // Rechterboog
  tekenDriehoek();        // Onderste punt
}

void setup() {
  u8g2.begin();
  pinMode(RODE_LED_PIN, OUTPUT);
  
  // Vul de array eenmalig met het kader en het hart
  genereerAfbeelding();
}

void loop() {
  // --- FASE 1: LED AAN -> ZWART SCHERM ---
  u8g2.clearBuffer();
  u8g2.sendBuffer();
  
  digitalWrite(RODE_LED_PIN, LOW); // LED aan
  delay(500);

  // --- FASE 2: LED UIT -> ARRAY TONEN ---
  u8g2.clearBuffer();
  
  // Stuur onze eigen frameBuffer array in één keer naar de OLED controller
  u8g2.drawXBM(0, 0, SCHERM_BREEDTE, SCHERM_HOOGTE, frameBuffer);
  u8g2.sendBuffer();
  
  digitalWrite(RODE_LED_PIN, HIGH); // LED uit
  delay(500);
}