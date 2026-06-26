#include "PairingMode.h"

#include <Arduino.h>
#include <BLEDevice.h>

#include <string>

#include "Logging.h"
#include "Utils.h"

PairingMode::PairingMode() {
}

class PairingAdvertisedDeviceCallbacks : public BLEAdvertisedDeviceCallbacks {
    void onResult(BLEAdvertisedDevice advertisedDevice) {
        auto deviceName = advertisedDevice.getName();
        auto deviceAddr = advertisedDevice.getAddress();

        Logging::info("PairingMode",
                      "Advertised Device: name=" + deviceName + ", addr=" + deviceAddr.toString());

        for (int i = 0; i < advertisedDevice.getServiceUUIDCount(); i++) {
            auto serviceUUID = advertisedDevice.getServiceUUID(i);
            Logging::info("PairingMode", "Service UUID: " + serviceUUID.toString());
        }

        if (advertisedDevice.haveManufacturerData()) {
            auto strManufacturerData = advertisedDevice.getManufacturerData();
            // BLE max is 255
            uint8_t byteManufacturerData[255];
            size_t manufacturerDataLength = strManufacturerData.length();
            if (manufacturerDataLength > sizeof(byteManufacturerData)) {
                Logging::warn("PairingMode",
                              "Manufacturer data too long, truncating to " + std::to_string(sizeof(byteManufacturerData)));
                manufacturerDataLength = sizeof(byteManufacturerData);
            }
            if (manufacturerDataLength > 0) {
                memcpy(byteManufacturerData, strManufacturerData.c_str(), manufacturerDataLength);
                Logging::info("PairingMode",
                              "Manufacturer Data: " +
                                  Utils::hexStr(byteManufacturerData, manufacturerDataLength));
            }
        }
    }
};

void PairingMode::setup() {
}

void PairingMode::loop() {
}
