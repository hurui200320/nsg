#ifndef PAIRING_SCANNER_H
#define PAIRING_SCANNER_H

#include <BLEDevice.h>

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
};  // namespace PairingScanner

#endif
