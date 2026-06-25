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
    explicit NikonPairingEngine(RandomGenerator &random_generator, BlowfishHasher &hasher);

    /**
     * Build stage 1. If saved_device and saved_nonce are non-null, their
     * values are reused.
     */
    PairingMessage create_stage1(const uint32_t *saved_device, const uint32_t *saved_nonce);

    /**
     * Verify the camera's stage-2 challenge, find the matching salt, and build
     * the stage-3 response. Returns a message with all zero if no salt matches.
     */
    PairingMessage verify_stage2_and_build_stage3(
        const PairingMessage &stage1,
        const PairingMessage &stage2
    );

    /**
     * Extract the 8-byte ASCII camera serial number from stage 4.
     *
     * The caller must ensure serial has room for at least 9 bytes
     * (8 characters + null terminator).
     */
    void extract_serial(const PairingMessage &stage4, char *serial);

private:
    RandomGenerator &random_generator;
    BlowfishHasher &hasher;

    static constexpr size_t SALT_COUNT = 8;

    static const uint32_t SALTS[SALT_COUNT][2];

    uint32_t generate_device_id();
    uint32_t generate_nonce();

    int find_salt(const PairingMessage &stage1, const PairingMessage &stage2);

    static void timestamp_halves_be(
        uint64_t timestamp,
        uint32_t &lo,
        uint32_t &hi
    );

    static uint32_t reverse_bytes_uint32(uint32_t value);
};

#endif // NIKON_PAIRING_ENGINE_H
