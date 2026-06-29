#include "PairedScanner.h"

#include <stdint.h>

#include "Logging.h"
#include "NikonUUID.h"

PairedScanner::PairedScanner() {
    // setup BLE
    pBLEScan = BLEDevice::getScan();
    // 10 cameras in pairing mode at the same time is kinda crazy
    scanResultQueue = xQueueCreate(10, sizeof(ScannedCamera));
}
PairedScanner::~PairedScanner() {
    stopScanning();
    vQueueDelete(scanResultQueue);
}

bool PairedScanner::startScanning() {
    // use self as callbacks, want duplicates since we need to check manufacturer data
    pBLEScan->setAdvertisedDeviceCallbacks(this, true, true);
    // Need active scan since it's too slow
    pBLEScan->setActiveScan(true);
    // scan interval in MS
    pBLEScan->setInterval(100);
    pBLEScan->setWindow(90);

    NSG_LOG_INFO("PairedScanner::startScanning", "start scanning...");
    // false to clear result, otherwise if camera's manufacturer data update,
    // callback will be skipped
    // this will basically scans forever
    return pBLEScan->start(UINT32_MAX, nullptr, false);
}

void PairedScanner::stopScanning() {
    pBLEScan->setAdvertisedDeviceCallbacks(nullptr, false, true);
    pBLEScan->stop();
    NSG_LOG_INFO("PairedScanner::stopScanning", "scanning stopped");
}

// Note: we never stop scanning

void PairedScanner::onResult(BLEAdvertisedDevice advertisedDevice) {
    // TODO: dedup with PairingScanner?

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
    uint32_t device = 0;
    if (advertisedDevice.haveManufacturerData()) {
        auto strManufacturerData = advertisedDevice.getManufacturerData();
        if (strManufacturerData.length() >= 6) {
            auto bytes = reinterpret_cast<const uint8_t*>(strManufacturerData.c_str());
            manufacturerDataKey = bytes[0] | bytes[1] << 8;
            device = static_cast<uint32_t>(bytes[2]) | static_cast<uint32_t>(bytes[3]) << 8 | static_cast<uint32_t>(bytes[4]) << 16 |
                     static_cast<uint32_t>(bytes[5]) << 24;
        }
    }
    // camera not paired
    if (manufacturerDataKey != 0x0399) return;

    NSG_LOG_DEBUG("PairedScanner::onResult", "found paired device %s, addr=%s", deviceName.c_str(), deviceAddr.toString().c_str());

    // create a queue message
    ScannedCamera camera;
    fillScannedCamera(&camera, deviceName, device, deviceAddr, advertisedDevice.getAddressType());

    if (!xQueueSend(scanResultQueue, &camera, (TickType_t)0)) {
        NSG_LOG_WARN("PairedScanner::onResult", "Queue full, discarding new items");
    }
}

void PairedScanner::fillScannedCamera(ScannedCamera* result, std::string deviceName, uint32_t device, BLEAddress deviceAddr, uint8_t addrType) {
    // copy name
    size_t cameraNameSize = 0;
    if (deviceName.length() >= sizeof(result->name) - 1) {
        cameraNameSize = sizeof(result->name) - 1;
        memcpy(result->name, deviceName.c_str(), cameraNameSize);
    } else {
        cameraNameSize = deviceName.length();
        memcpy(result->name, deviceName.c_str(), cameraNameSize);
    }
    result->name[cameraNameSize] = 0;
    // copy BLE address
    memcpy(result->addr, deviceAddr.getNative(), ESP_BD_ADDR_LEN);
    // set addrType and device
    result->addrType = addrType;
    result->device = device;
}
