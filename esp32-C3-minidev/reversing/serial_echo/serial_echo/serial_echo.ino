#include <Arduino.h>

void setup() {
  // Start seriële communicatie op 115200 baud
  Serial.begin(115200);
  
  // Wacht even tot de seriële poort gereed is
  while (!Serial) {
    delay(10);
  }
  
  Serial.println("Arduino Serial Echo Ready");
}

void loop() {
  // Controleer of er data klaarstaat en echo het direct terug
  if (Serial.available() > 0) {
    char incomingByte = Serial.read();
    Serial.write(incomingByte);
  }
}