/**
 * C++ port of NikonPairingEngine from kotlin-poc.
 *
 * Drives the 4-stage Nikon smart-device pairing handshake.
 *
 * Pair mode generates fresh device and nonce via the injected RandomGenerator.
 * Reconnect mode reuses the supplied saved values. The timestamp is always
 * freshly generated.
 */

#ifndef NIKON_PAIRING_ENGINE_H
#define NIKON_PAIRING_ENGINE_H

#include <cstdint>

#include "BlowfishHasher.h"
#include "PairingMessage.h"
#include "RandomGenerator.h"

class NikonPairingEngine {
public:
    explicit NikonPairingEngine(RandomGenerator &randomGenerator, BlowfishHasher &hasher);

    /**
     * Build stage 1. If savedDevice and savedNonce are non-null, their
     * values are reused.
     */
    PairingMessage createStage1(const uint32_t *savedDevice, const uint32_t *savedNonce);

    /**
     * Verify the camera's stage-2 challenge, find the matching salt, and build
     * the stage-3 response. Returns a message with all zero if no salt matches.
     */
    PairingMessage verifyStage2AndBuildStage3(
        const PairingMessage &stage1,
        const PairingMessage &stage2
    );

    /**
     * Extract the 8-byte ASCII camera serial number from stage 4.
     *
     * The caller must ensure serial has room for at least 9 bytes
     * (8 characters + null terminator).
     */
    void extractSerial(const PairingMessage &stage4, char *serial);

private:
    RandomGenerator &randomGenerator;
    BlowfishHasher &hasher;

    static constexpr size_t SALT_COUNT = 8;

    static const uint32_t SALTS[SALT_COUNT][2];

    uint32_t generateDeviceId();
    uint32_t generateNonce();

    int findSalt(const PairingMessage &stage1, const PairingMessage &stage2);

    static void timestampHalvesBe(
        uint64_t timestamp,
        uint32_t &lo,
        uint32_t &hi
    );

    static uint32_t reverseBytesUInt32(uint32_t value);
};

#endif // NIKON_PAIRING_ENGINE_H
