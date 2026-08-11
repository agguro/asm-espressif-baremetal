#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Wire.h>

#define LED_PIN 8
#define SSD1306_I2C_ADDR 0x3C

// Standard Nordic UART Service (NUS) UUIDs
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// --- FRAMEBUFFER (72x40 pixels = 72 columns * 5 pages = 360 bytes) ---
uint8_t framebuffer[360];

// State variables and timing (Interval = 2,000,000 microseconds = 2 seconds)
enum LedMode { LED_MODE_OFF, LED_MODE_ON, LED_MODE_BLINK };
enum OledMode { OLED_MODE_STATIC, OLED_MODE_BLINK };

LedMode currentLedMode = LED_MODE_OFF;
OledMode currentOledMode = OLED_MODE_STATIC;

unsigned long ledPrevMicros = 0;
unsigned long oledPrevMicros = 0;
const unsigned long INTERVAL = 2000000; 

bool ledState = false;
bool oledBlinkState = false;

// --- RAW SSD1306 DRIVER FUNCTIONS ---
void ssd1306_send_cmd(uint8_t cmd) {
    Wire.beginTransmission(SSD1306_I2C_ADDR);
    Wire.write(0x00); // Command stream control byte
    Wire.write(cmd);
    Wire.endTransmission();
}

void ssd1306_init() {
    delay(100);
    ssd1306_send_cmd(0xAE); // Display OFF
    ssd1306_send_cmd(0xD5); ssd1306_send_cmd(0x80); // Display clock divide ratio
    ssd1306_send_cmd(0xA8); ssd1306_send_cmd(0x27); // Multiplex ratio (40 rows for 72x40)
    ssd1306_send_cmd(0xD3); ssd1306_send_cmd(0x00); // Display offset
    ssd1306_send_cmd(0x40); // Start line address
    ssd1306_send_cmd(0x8D); ssd1306_send_cmd(0x14); // Charge pump setting
    ssd1306_send_cmd(0x20); ssd1306_send_cmd(0x00); // Horizontal addressing mode
    ssd1306_send_cmd(0xA1); // Segment re-map
    ssd1306_send_cmd(0xC8); // COM output scan direction
    ssd1306_send_cmd(0xDA); ssd1306_send_cmd(0x12); // COM pins hardware configuration
    ssd1306_send_cmd(0x81); ssd1306_send_cmd(0xCF); // Contrast control
    ssd1306_send_cmd(0xD9); ssd1306_send_cmd(0xF1); // Pre-charge period
    ssd1306_send_cmd(0xDB); ssd1306_send_cmd(0x40); // VCOMH deselect level
    ssd1306_send_cmd(0xA4); // Resume to RAM content
    ssd1306_send_cmd(0xA6); // Normal display (not inverted)
    ssd1306_send_cmd(0xAF); // Display ON
}

// Push the full RAM framebuffer to the display over I2C
void oled_flush() {
    // Set column window (Columns 28 to 99 for 72x40 centered display)
    ssd1306_send_cmd(0x21); ssd1306_send_cmd(28); ssd1306_send_cmd(99);
    // Set page window (Pages 0 to 4)
    ssd1306_send_cmd(0x22); ssd1306_send_cmd(0); ssd1306_send_cmd(4);

    size_t index = 0;
    while (index < 360) {
        Wire.beginTransmission(SSD1306_I2C_ADDR);
        Wire.write(0x40); // Data stream control byte
        size_t chunk = (360 - index < 16) ? (360 - index) : 16;
        for (size_t i = 0; i < chunk; i++) {
            Wire.write(framebuffer[index + i]);
        }
        Wire.endTransmission();
        index += chunk;
    }
}

// Fill framebuffer with a pattern (e.g., 0x00 for black, 0xFF for white) and flush
void oled_fill(uint8_t pattern) {
    for (int i = 0; i < 360; i++) {
        framebuffer[i] = pattern;
    }
    oled_flush();
}

// --- COMMAND HANDLER (Unified for BLE & USB Serial) ---
void handleCommand(String cmd, bool sendViaBle) {
    cmd.trim();
    cmd.toLowerCase();

    if (cmd.length() > 0) {
        String response = "";

        if (cmd == "led on") {
            currentLedMode = LED_MODE_ON;
            digitalWrite(LED_PIN, LOW); // Active low LED ON
            response = "LED is now ON\r\n";
            Serial.println("[CMD] LED turned ON");
        } 
        else if (cmd == "led off") {
            currentLedMode = LED_MODE_OFF;
            digitalWrite(LED_PIN, HIGH); // LED OFF
            response = "LED is now OFF\r\n";
            Serial.println("[CMD] LED turned OFF");
        } 
        else if (cmd == "led blink") {
            currentLedMode = LED_MODE_BLINK;
            response = "LED is now BLINKING\r\n";
            Serial.println("[CMD] LED blinking activated");
        }
        else if (cmd == "oled on") {
            currentOledMode = OLED_MODE_STATIC;
            oled_fill(0xFF); // All pixels white
            response = "OLED is now ON (all white)\r\n";
            Serial.println("[CMD] OLED turned ON");
        }
        else if (cmd == "oled off") {
            currentOledMode = OLED_MODE_STATIC;
            oled_fill(0x00); // All pixels black
            response = "OLED is now OFF (all black)\r\n";
            Serial.println("[CMD] OLED turned OFF");
        }
        else if (cmd == "oled blink") {
            currentOledMode = OLED_MODE_BLINK;
            response = "OLED is now BLINKING\r\n";
            Serial.println("[CMD] OLED blinking activated");
        }
        else if (cmd == "status") {
            response = "ESP32-C3 online & operational\r\n";
            Serial.println("[CMD] Status requested");
        } 
        else {
            response = "Echo: " + cmd + "\r\n";
            Serial.print("[Echo]: ");
            Serial.println(cmd);
        }

        // Send response back via BLE notification if connected
        if (sendViaBle && deviceConnected) {
            pTxCharacteristic->setValue(response);
            pTxCharacteristic->notify();
        }
    }
}

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnected(BLEServer* pServer) {
        deviceConnected = true;
        Serial.println("[BLE] Device connected!");
    }

    void onDisconnected(BLEServer* pServer) {
        deviceConnected = false;
        Serial.println("[BLE] Device disconnected. Restarting advertising...");
        pServer->getAdvertising()->start();
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        String rxValue = pCharacteristic->getValue();
        handleCommand(rxValue, true);
    }
};

void setup() {
    Serial.begin(115200);
    delay(1000);
    Serial.println("\n[Init] Starting ESP32-C3 Framebuffer Server...");

    // Initialize I2C on SDA=5, SCL=6
    Wire.begin(5, 6);
    ssd1306_init();
    oled_fill(0x00); // Start with clear/black screen

    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, HIGH); // Default OFF

    // BLE Setup
    BLEDevice::init("ESP32");
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    BLEService *pService = pServer->createService(SERVICE_UUID);

    pTxCharacteristic = pService->createCharacteristic(
                            CHARACTERISTIC_UUID_TX,
                            BLECharacteristic::PROPERTY_NOTIFY
                        );
    pTxCharacteristic->addDescriptor(new BLE2902());

    BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(
                                            CHARACTERISTIC_UUID_RX,
                                            BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
                                        );
    pRxCharacteristic->setCallbacks(new MyCallbacks());

    pService->start();

    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMinPreferred(0x12);
    pAdvertising->start();

    Serial.println("[Ready] Send 'led on/off/blink' or 'oled on/off/blink' via picocom or BLE app.");
}

void loop() {
    // Check for incoming data from USB Serial (picocom)
    if (Serial.available() > 0) {
        String serialInput = Serial.readStringUntil('\n');
        handleCommand(serialInput, false);
    }

    unsigned long currentMicros = micros();

    // Non-blocking LED blink (2,000,000 µs interval)
    if (currentLedMode == LED_MODE_BLINK) {
        if (currentMicros - ledPrevMicros >= INTERVAL) {
            ledPrevMicros = currentMicros;
            ledState = !ledState;
            digitalWrite(LED_PIN, ledState ? LOW : HIGH);
        }
    }

    // Non-blocking OLED blink (2,000,000 µs interval)
    if (currentOledMode == OLED_MODE_BLINK) {
        if (currentMicros - oledPrevMicros >= INTERVAL) {
            oledPrevMicros = currentMicros;
            oledBlinkState = !oledBlinkState;
            oled_fill(oledBlinkState ? 0xFF : 0x00);
        }
    }

    if (!deviceConnected && oldDeviceConnected) {
        delay(500); 
        oldDeviceConnected = deviceConnected;
    }
    
    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = deviceConnected;
    }

    delay(1);
}
