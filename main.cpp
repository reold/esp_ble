#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>

#define SERVICE_UUID        "0000FFFF-0000-1000-8000-00805F9B34FB"
#define CHARACTERISTIC_UUID "0000FF01-0000-1000-8000-00805F9B34FB"
#define DEVICE_NAME         "esp32"

BLEServer* pServer = nullptr;
BLEService* pService = nullptr;
BLECharacteristic* rxChar = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("[BLE] Client connected");
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("[BLE] Client disconnected");
  }
};

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    std::string v = c->getValue();
    if (v.empty()) return;

    // log the message
    Serial.printf("[BLE] Received (%u bytes): %s\n", (unsigned)v.size(), v.c_str());
  }
};

static void setupBLE() {
  Serial.println("[BLE] Initializing BLE...");
  
  BLEDevice::init(DEVICE_NAME);
  
  // Set MTU size (optional, but can help with larger messages)
  BLEDevice::setMTU(517);

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  pService = pServer->createService(SERVICE_UUID);

  rxChar = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  rxChar->setCallbacks(new RxCallbacks());

  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // functions that help with iPhone connections issue
  pAdvertising->setMinPreferred(0x12);
  
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Advertising started — device discoverable");
}

void setup() {
  Serial.begin(115200);
  delay(200);

  Serial.println("[SYS] Starting ESP32 BLE Server...");
  
  setupBLE();

  Serial.println("[SYS] Boot complete");
}

void loop() {
  // Handle disconnection and restart advertising
  if (!deviceConnected && oldDeviceConnected) {
    delay(500); // give the bluetooth stack the chance to get things ready
    pServer->startAdvertising(); // restart advertising
    Serial.println("[BLE] Restarting advertising");
    oldDeviceConnected = deviceConnected;
  }
  
  // Handle new connection
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }
  
  delay(10);
}