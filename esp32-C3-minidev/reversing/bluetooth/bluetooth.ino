#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// Standaard Nordic UART Service (NUS) UUIDs
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Callback voor verbindingsstatus
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnected(BLEServer* pServer) {
        deviceConnected = true;
        Serial.println("[BLE] Apparaat verbonden!");
    }

    void onDisconnected(BLEServer* pServer) {
        deviceConnected = false;
        Serial.println("[BLE] Apparaat verbroken.");
    }
};

// Callback voor inkomende data van de telefoon (RX)
// Callback voor inkomende data van de telefoon (RX)
class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        String rxValue = pCharacteristic->getValue(); // Gebruik Arduino String

        if (rxValue.length() > 0) {
            Serial.print("[Ontvangen via BLE]: ");
            for (int i = 0; i < rxValue.length(); i++) {
                Serial.print(rxValue[i]);
            }
            Serial.println();

            // Nu rxValue een Arduino String is, pakt setValue dit direct op
            pTxCharacteristic->setValue(rxValue);
            pTxCharacteristic->notify();
        }
    }
};

void setup() {
    Serial.begin(115200);
    delay(1000);
    Serial.println("\n[Init] Start BLE UART Server...");

    // 1. Initialiseer BLE apparaat met een herkenbare naam
    BLEDevice::init("ESP32C3_UART");

    // 2. Maak de BLE Server aan
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    // 3. Maak de BLE Service aan
    BLEService *pService = pServer->createService(SERVICE_UUID);

    // 4. Maak de TX Characteristic (om data *naar* de telefoon te sturen)
    pTxCharacteristic = pService->createCharacteristic(
                            CHARACTERISTIC_UUID_TX,
                            BLECharacteristic::PROPERTY_NOTIFY
                        );
    pTxCharacteristic->addDescriptor(new BLE2902());

    // 5. Maak de RX Characteristic (om data *van* de telefoon te ontvangen)
    BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(
                                            CHARACTERISTIC_UUID_RX,
                                            BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
                                        );
    pRxCharacteristic->setCallbacks(new MyCallbacks());

    // 6. Start de service
    pService->start();

    // 7. Start adverteren zodat telefoons het apparaat kunnen vinden
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);  // helpt bij iPhone connecties
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("[Klaar] BLE is actief. Zoek naar 'ESP32C3_UART' op je telefoon.");
}

void loop() {
    // Beheer het opnieuw opstarten van adverteren als de verbinding wegvalt
    if (!deviceConnected && oldDeviceConnected) {
        delay(500); // geef de bluetooth stack even de tijd
        pServer->startAdvertising(); 
        Serial.println("[BLE] Opnieuw aan het adverteren...");
        oldDeviceConnected = deviceConnected;
    }
    
    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = deviceConnected;
    }

    delay(100);
}
