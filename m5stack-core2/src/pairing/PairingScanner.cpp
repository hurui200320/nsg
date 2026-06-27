#include "PairingScanner.h"

#include <stdint.h>

#include "Logging.h"
#include "NikonUUID.h"
#include "PairingModels.h"

PairingScanner::PairingScanner() {
    pBLEScan = BLEDevice::getScan();
    // 10 cameras in pairing mode at the same time is kinda crazy
    scanResultQueue = xQueueCreate(10, sizeof(Camera));
}

void PairingScanner::startScanning() {
    // use self as callbacks, want duplicates since we need to check manufacturer data
    pBLEScan->setAdvertisedDeviceCallbacks(this, true, true);
    // use more power, but actively asking devices, faster
    pBLEScan->setActiveScan(true);
    // scan interval in MS
    pBLEScan->setInterval(100);
    // window for active scan, in MS
    pBLEScan->setWindow(90);

    Logging::info("PairingScanner::startScanning", "start scanning...");
    // false to clear result, otherwise if camera's manufacturer data update,
    // callback will be skipped
    // this will basically scans forever
    if(!pBLEScan->start(UINT32_MAX, nullptr, false)) {
        Logging::fatal("PairingScanner::startScanning", "failed to start BLE scanning");
    }
}

void PairingScanner::stopScanning() {
    pBLEScan->setAdvertisedDeviceCallbacks(nullptr, false, true);
    pBLEScan->stop();
    Logging::info("PairingScanner::stopScanning", "scanning stopped");
}

void PairingScanner::onResult(BLEAdvertisedDevice advertisedDevice) {
    // Nikon device name will have false length,
    // for example: length()=25 but only have 13 chars, the rest will be 0
    // this will cause any string concatnated after the name being truncated
    // thus we need to clean it by deepcopy the true string into a new string obj
    auto deviceName = std::string(advertisedDevice.getName().c_str());

    // missing device name
    if (deviceName.length() <= 4) return;

    auto deviceAddr = advertisedDevice.getAddress();

    bool hasNikonServiceUUID = false;

    for (int i = 0; i < advertisedDevice.getServiceUUIDCount(); i++) {
        auto serviceUUID = advertisedDevice.getServiceUUID(i);
        auto serviceUUIDStr = serviceUUID.toString();
        if (serviceUUIDStr == NikonUUID::SERVICE) {
            hasNikonServiceUUID = true;
            break;
        }
    }
    // no nikon service uuid
    if (!hasNikonServiceUUID) return;

    // First two bytes of manufacture data, parse in LE
    uint16_t manufacturerDataKey = 0;
    if (advertisedDevice.haveManufacturerData()) {
        auto strManufacturerData = advertisedDevice.getManufacturerData();
        if (strManufacturerData.length() >= 2) {
            auto bytes = reinterpret_cast<const uint8_t*>(strManufacturerData.c_str());
            manufacturerDataKey = bytes[0] | bytes[1] << 8;
        }
    }
    // camera already paired
    if (manufacturerDataKey == 0x0399) return;

    // create a queue message
    Camera camera;
    size_t cameraNameSize = 0;
    if (deviceName.length() >= sizeof(camera.name) - 1) {
        cameraNameSize = sizeof(camera.name) - 1;
        memcpy(camera.name, deviceName.c_str(), cameraNameSize);
        camera.name[cameraNameSize] = 0;
    } else {
        cameraNameSize = deviceName.length();
        memcpy(camera.name, deviceName.c_str(), cameraNameSize);
        camera.name[cameraNameSize] = 0;
    }
    size_t cameraAddrSize = sizeof(camera.addr) - 1;
    memcpy(camera.addr, deviceAddr.toString().c_str(), cameraAddrSize);
    camera.addr[cameraAddrSize] = 0;
    camera.addrType = advertisedDevice.getAddressType();

    if (!xQueueSend(scanResultQueue, &camera, (TickType_t)0)) {
        Logging::warn("PairingBLE::processScanResult", "Queue full, cannot post new items");
    }
}
