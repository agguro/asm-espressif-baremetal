#include <Arduino.h>
#include <U8g2lib.h>
#include <Wire.h>

// We initialiseren het scherm (SSD1306 via I2C, 72x40 of 128x64 resolutie)
// We dwingen de I2C pinnen expliciet naar GPIO 5 (SDA) en GPIO 6 (SCL)
U8G2_SSD1306_72X40_ER_F_HW_I2C u8g2(U8G2_R0, /* reset=*/ U8X8_PIN_NONE, /* clock=*/ 6, /* data=*/ 5);

void setup() {
  // Start de display-engine
  u8g2.begin();
}

void loop() {
  u8g2.clearBuffer();					// Wis het interne geheugen
  u8g2.setFont(u8g2_font_ncenB08_tr);	// Kies een compact, duidelijk lettertype
  u8g2.drawStr(0, 15, "I'm");		// Schrijf tekst op positie X=0, Y=15
  u8g2.drawStr(0, 32, "ALIVE");		// Schrijf tekst op positie X=0, Y=32
  u8g2.sendBuffer();					// Stuur het beeld daadwerkelijk naar het scherm
  
  delay(1000);
}