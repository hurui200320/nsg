#ifndef NIKON_BLE_CLIENT_H
#define NIKON_BLE_CLIENT_H

#include <BLEClient.h>
#include <inttypes.h>
#include <memory>

#include "BlowfishHasher.h"
#include "GeoMessage.h"
#include "NikonPairingEngine.h"
#include "PairingMessage.h"
#include "RandomGenerator.h"
#include "TimeMessage.h"

// Timeout for a single BLE (re)connect attempt (the BLEClient::connect call
// in doHandshake). A camera going idle keeps broadcasting but takes longer
// (~30s) to accept the connection, so this must cover that comfortably.
// Shared with the NIKON_BLE_CLIENT_DEADLINE_MS static_assert in BleWorker.h
// so the two cannot drift apart.
#ifndef NIKON_BLE_CONNECT_TIMEOUT_MS
#define NIKON_BLE_CONNECT_TIMEOUT_MS 45000
#endif

class NikonBLEClient {
   public:
    explicit NikonBLEClient(RandomGenerator& randomGenerator);
    NikonBLEClient(RandomGenerator& randomGenerator, const uint32_t savedDevice, const uint32_t savedNonce);
    ~NikonBLEClient();

    // Non-copyable: the BLE client is a unique resource.
    NikonBLEClient(const NikonBLEClient&) = delete;
    NikonBLEClient& operator=(const NikonBLEClient&) = delete;
    // Non-movable due to NikonPairingEngine's blowfish hash
    NikonBLEClient(NikonBLEClient&&) = delete;
    NikonBLEClient& operator=(NikonBLEClient&&) = delete;

    // return false means failed to handshake
    bool doHandshake(BLEAddress address, const uint8_t type);
    bool isConnected();
    void disconnect();
    uint32_t getDevice();
    uint32_t getNonce();

    // send payload after handshake
    bool sendTimePayload(TimeMessage& message);
    bool sendGeoPayload(GeoMessage& message);

   private:
    RandomGenerator& rnd;
    BlowfishHasher hasher;
    NikonPairingEngine engine;
    uint32_t device;
    uint32_t nonce;
    PairingMessage stage1Message;
    PairingMessage stage2Message;
    PairingMessage stage3Message;
    PairingMessage stage4Message;

    std::unique_ptr<BLEClient> pClient;
    BLERemoteService* nikonService;
    BLERemoteCharacteristic* timeChar;
    BLERemoteCharacteristic* geoChar;
};

#endif