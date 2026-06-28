#ifndef PAIRED_SCANNER_H
#define PAIRED_SCANNER_H

#include <BLEDevice.h>
#include "../common/ScannedCamera.h"
#include<string>

class PairedScanner : public BLEAdvertisedDeviceCallbacks {
   public:
    PairedScanner();
    bool startScanning();
    void stopScanning();
    
    // read/receive Camera value from here
    QueueHandle_t scanResultQueue;

   private:
    BLEScan* pBLEScan;
    // callback
    void onResult(BLEAdvertisedDevice advertisedDevice) override;
    // fill a ScannedCamera object
    void fillScannedCamera(ScannedCamera* result, String deviceName, uint32_t device, BLEAddress deviceAddr, uint8_t addrType);
}; 

#endif
