#include <Arduino.h>
#include <U8g2lib.h>
#include <Wire.h>

// Scherm initialisatie (GPIO 5 = SDA, GPIO 6 = SCL)
U8G2_SSD1306_72X40_ER_F_HW_I2C u8g2(U8G2_R0, /* reset=*/ U8X8_PIN_NONE, /* clock=*/ 6, /* data=*/ 5);

void setup() {
  u8g2.begin();
  
  u8g2.clearBuffer();
  
  // We zetten de kleur op wit (pixels aan)
  u8g2.setDrawColor(1);
  
  // --- De twee bovenste bogen van het hart (gevulde cirkels) ---
  // drawDisc(X, Y, straal)
  u8g2.drawDisc(28, 14, 7); // Linkerboog
  u8g2.drawDisc(42, 14, 7); // Rechterboog
  
  // --- De onderste punt van het hart (gevulde driehoek) ---
  // drawTriangle(X1, Y1, X2, Y2, X3, Y3)
  u8g2.drawTriangle(21, 17, 49, 17, 35, 36);
  
  u8g2.sendBuffer();
}

void loop() {
  // Geen loops of flikkeringen, gewoon een strak beeld
}