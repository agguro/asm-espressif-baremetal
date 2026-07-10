#include <Arduino.h>
#include <U8g2lib.h>
#include <Wire.h>

// Scherm initialisatie (GPIO 5 = SDA, GPIO 6 = SCL)
U8G2_SSD1306_72X40_ER_F_HW_I2C u8g2(U8G2_R0, /* reset=*/ U8X8_PIN_NONE, /* clock=*/ 6, /* data=*/ 5);

// De tekst die je wilt laten lopen (verander dit gerust!)
const char* lopendeTekst = "*** Hola, mi hombre. Como estas? ***";

int displayBreedte;
int tekstBreedte;
int xPositie;

void setup() {
  u8g2.begin();
  
  // Kies een mooi, strak en leesbaar lettertype
  u8g2.setFont(u8g2_font_7x14_tf); 
  
  // Vraag de fysieke breedte van je scherm op (meestal 72 of 128 pixels)
  displayBreedte = u8g2.getDisplayWidth();
  
  // Bereken exact hoeveel pixels breed de tekst is in het gekozen lettertype
  tekstBreedte = u8g2.getStrWidth(lopendeTekst);
  
  // We starten de tekst net buiten het scherm aan de rechterkant
  xPositie = displayBreedte;
}

void loop() {
  u8g2.clearBuffer(); // Wis het schermgeheugen voor de volgende frame
  
  // Teken de tekst op de huidige X-positie. 
  // Y = 25 zet de tekst mooi verticaal gecentreerd op het schermpje.
  u8g2.drawStr(xPositie, 25, lopendeTekst);
  
  u8g2.sendBuffer(); // Stuur de buffer naar het OLED-scherm
  
  // Verschuif de tekst 1 pixel naar links
  xPositie = xPositie - 1;
  
  // Als de tekst helemaal voorbij de linkerkant van het scherm is geschoven,
  // resetten we de positie naar de rechterkant om opnieuw te beginnen.
  if (xPositie < -tekstBreedte) {
    xPositie = displayBreedte;
  }
  
  // Snelheid van het scrollen (lager getal = sneller, hoger = trager)
  delay(15); 
}