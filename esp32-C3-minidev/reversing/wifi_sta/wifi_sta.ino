#include <WiFi.h>
#include <WebServer.h>

const char* ssid = "ESP32-S3-Server";
const char* password = "bienvenido12345";

WebServer server(80);

// 1. Toont de webpagina met een invoerveld voor de naam
void handleRoot() {
  String html = "<!DOCTYPE html>";
  html += "<html><head><meta charset='utf-8'><title>Introduce tu nombre</title>";
  html += "<style>body{font-family:sans-serif; text-align:center; margin-top:50px; background:#f0f0f0;}";
  html += "input{padding:10px; font-size:16px;} button{padding:10px 20px; font-size:16px; background:#007BFF; color:white; border:none; cursor:pointer;}";
  html += "</style></head><body>";
  html += "<h1>¿Cómo te llamas?</h1>";
  html += "<form action='/welkom' method='POST'>";
  html += "<input type='text' name='naam' placeholder='Escribe tu nombre aquí...' required><br><br>";
  html += "<button type='submit'>Enviar</button>";
  html += "</form>";
  html += "</body></html>";
  
  server.send(200, "text/html", html);
}

// 2. Vangt de POST op, haalt de naam eruit en toont de begroeting
void handleWelkom() {
  if (server.hasArg("naam")) {
    String ingevoerdeNaam = server.arg("naam");
    
    String responseHtml = "<!DOCTYPE html>";
    responseHtml += "<html><head><meta charset='utf-8'><title>Bienvenido</title>";
    responseHtml += "<style>body{font-family:sans-serif; text-align:center; margin-top:50px; background:#e8f5e9;}";
    responseHtml += "h1{color:#2e7d32;}</style></head><body>";
    responseHtml += "<h1>¡bienvenido " + ingevoerdeNaam + "!</h1>";
    responseHtml += "<br><a href='/'>Volver</a>";
    responseHtml += "</body></html>";

    server.send(200, "text/html", responseHtml);
  } else {
    server.send(400, "text/text", "¡No se ha recibido ningún nombre!");
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  // Start Access Point
  WiFi.softAP(ssid, password);
  Serial.print("AP IP-adres: ");
  Serial.println(WiFi.softAPIP());

  // Koppel de routes
  server.on("/", HTTP_GET, handleRoot);
  server.on("/welkom", HTTP_POST, handleWelkom);

  server.begin();
  Serial.println("HTTP-server gestart.");
}

void loop() {
  server.handleClient();
}