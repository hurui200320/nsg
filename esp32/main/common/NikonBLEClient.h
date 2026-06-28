#ifndef NIKON_BLE_CLIENT_H
#define NIKON_BLE_CLIENT_H

#include <BLEClient.h>

#include "BlowfishHasher.h"
#include "Esp32RandomGenerator.h"
#include "NikonPairingEngine.h"
#include "PairingMessage.h"

class NikonBLEClient {
   public:
    NikonBLEClient();
    NikonBLEClient(uint32_t savedDevice, uint32_t savedNonce);
    ~NikonBLEClient();

    // return false means failed to handshake
    bool doHandshake(BLEAddress address, uint8_t type);
    bool isConnnected();
    void disconnect();
    uint32_t getDevice();
    uint32_t getNonce();

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
};

#endif