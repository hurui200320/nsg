#ifndef PAIRING_SCANNER_H
#define PAIRING_SCANNER_H

#include <BLEDevice.h>
#include "../common/ScannedCamera.h"

class PairingScanner : public BLEAdvertisedDeviceCallbacks {
   public:
    PairingScanner();
    void startScanning();
    void stopScanning();
    // read/receive Camera value from here
    QueueHandle_t scanResultQueue;

   private:
    BLEScan* pBLEScan;
    // callback
    void onResult(BLEAdvertisedDevice advertisedDevice) override;
    // fill a ScannedCamera object
    void fillScannedCamera(ScannedCamera* result, std::string deviceName, BLEAddress deviceAddr, esp_ble_addr_type_t addrType);
};

#endif
