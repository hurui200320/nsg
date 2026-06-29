#ifndef NIKON_BLE_CLIENT_H
#define NIKON_BLE_CLIENT_H

#include <BLEClient.h>
#include <inttypes.h>

#include "BlowfishHasher.h"
#include "Esp32RandomGenerator.h"
#include "GeoMessage.h"
#include "NikonPairingEngine.h"
#include "PairingMessage.h"
#include "TimeMessage.h"

class NikonBLEClient {
   public:
    NikonBLEClient();
    NikonBLEClient(const uint32_t savedDevice, const uint32_t savedNonce);
    ~NikonBLEClient();

    // return false means failed to handshake
    bool doHandshake(BLEAddress address, const uint8_t type);
    bool isConnnected();
    void disconnect();
    uint32_t getDevice();
    uint32_t getNonce();

    // send payload after handshake
    bool sendTimePayload(TimeMessage& message);
    bool sendGeoPayload(GeoMessage& message);

   private:
    Esp32RandomGenerator rnd;
    BlowfishHasher hasher;
    NikonPairingEngine engine;
    uint32_t device;
    uint32_t nonce;
    PairingMessage stage1Message;
    PairingMessage stage2Message;
    PairingMessage stage3Message;
    PairingMessage stage4Message;

    BLEClient* pClient;
    BLERemoteService* nikonService;
    BLERemoteCharacteristic* timeChar;
    BLERemoteCharacteristic* geoChar;
};

#endif