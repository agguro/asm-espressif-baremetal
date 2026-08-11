#include <Arduino.h>
#include <WiFi.h>
#include <U8g2lib.h>
#include <Wire.h>

// Scherm initialisatie (GPIO 5 = SDA, GPIO 6 = SCL)
U8G2_SSD1306_72X40_ER_F_HW_I2C u8g2(U8G2_R0, /* reset=*/ U8X8_PIN_NONE, /* clock=*/ 6, /* data=*/ 5);

// Jouw Telenet netwerkgegevens
const char* ssid     = "telenet-DA9B1";
const char* password = "529M80vGS7M7";

void setup() {
  // 1. Start het scherm
  u8g2.begin();
  u8g2.setFont(u8g2_font_6x10_tf);
  
  u8g2.clearBuffer();
  u8g2.drawStr(0, 12, "Connecting...");
  u8g2.drawStr(0, 28, "Met Telenet");
  u8g2.sendBuffer();

  // 2. Wi-Fi opstarten in Client (Station) modus
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  // Status controleren met een maximale timeout (30 pogingen van 500ms = 15 seconden)
  int pogingen = 0;
  while (WiFi.status() != WL_CONNECTED && pogingen < 30) {
    delay(500);
    pogingen++;
    
    // Toon een simpel voortgangspuntje op het scherm
    u8g2.clearBuffer();
    u8g2.drawStr(0, 12, "Connecting...");
    char st[16];
    sprintf(st, "attempt: %d/30", pogingen);
    u8g2.drawStr(0, 28, st);
    u8g2.sendBuffer();
  }

  // 3. Resultaat tonen
  u8g2.clearBuffer();
  if (WiFi.status() == WL_CONNECTED) {
    // Succes! Toon het gekregen IP-adres
    u8g2.drawStr(0, 10, "Connected!");
    
    IPAddress IP = WiFi.localIP();
    char ipStr[16];
    sprintf(ipStr, "%d.%d.%d.%d", IP[0], IP[1], IP[2], IP[3]);
    u8g2.drawStr(0, 24, ipStr);
    
    // Toon de signaalsterkte (RSSI) in dBm
    char rssiStr[16];
    sprintf(rssiStr, "RSSI: %d dBm", WiFi.RSSI());
    u8g2.drawStr(0, 38, rssiStr);
  } else {
    // Timeout bereikt, netwerk niet gevonden of verkeerd wachtwoord
    u8g2.drawStr(0, 12, "Fout: Geen");
    u8g2.drawStr(0, 28, "verbinding!");
  }
  u8g2.sendBuffer();
}

void loop() {
  // De loop blijft leeg. Eenmaal verbonden blijft de verbinding op de 
  // achtergrond in stand gehouden door de netwerkstack van de C3.
}