#include <Arduino.h>
#include <U8g2lib.h>
#include <Wire.h>

// Scherm initialisatie (GPIO 5 = SDA, GPIO 6 = SCL)
U8G2_SSD1306_72X40_ER_F_HW_I2C u8g2(U8G2_R0, /* reset=*/ U8X8_PIN_NONE, /* clock=*/ 6, /* data=*/ 5);

// Pin voor het ingebouwde rode ledje
#define RODE_LED_PIN 8

void setup() {
  u8g2.begin();
  pinMode(RODE_LED_PIN, OUTPUT);
  u8g2.setDrawColor(1);
}

void loop() {
  // --- FASE 1: LED AAN -> ZWART SCHERM ---
  // Wis de buffer (alles zwart) en stuur naar het scherm
  u8g2.clearBuffer();
  u8g2.sendBuffer();
  
  // Led aan (LOW is aan bij active-low)
  digitalWrite(RODE_LED_PIN, LOW);
  delay(500);

  // --- FASE 2: LED UIT -> HARTJE TONEN ---
  // Wis de buffer en teken het strakke pixel-hart opnieuw
  u8g2.clearBuffer();
  u8g2.drawDisc(28, 14, 7);                  // Linkerboog
  u8g2.drawDisc(42, 14, 7);                  // Rechterboog
  u8g2.drawTriangle(21, 17, 49, 17, 35, 36); // Onderste punt
  u8g2.sendBuffer();
  
  // Led uit (HIGH is uit bij active-low)
  digitalWrite(RODE_LED_PIN, HIGH);
  delay(500);
}