#include "NikonPairingEngine.h"

#include <cstring>

const uint32_t NikonPairingEngine::SALTS[SALT_COUNT][2] = {
    {0x704066e4U, 0x0433d552U},
    {0xed4b8facU, 0x15f7e47bU},
    {0x24471f11U, 0x8b5ea1fcU},
    {0x05960c31U, 0x2b8c7f41U},
    {0xfda588c1U, 0xeba8b1f3U},
    {0x99166056U, 0x1bd3d550U},
    {0xcd32687fU, 0xa9e28a30U},
    {0x2a8fe834U, 0xdec7ebf4U}
};

NikonPairingEngine::NikonPairingEngine(RandomGenerator &randomGenerator, BlowfishHasher &hasher)
    : randomGenerator(randomGenerator), hasher(hasher) {
}

PairingMessage NikonPairingEngine::createStage1(
    const uint32_t *savedDevice,
    const uint32_t *savedNonce
) {
    const uint64_t timestamp = randomGenerator.nextUInt64();
    const uint32_t device = savedDevice != nullptr ? *savedDevice : generateDeviceId();
    const uint32_t nonce = savedNonce != nullptr ? *savedNonce : generateNonce();

    return PairingMessage(0x01, timestamp, device, nonce);
}

PairingMessage NikonPairingEngine::verifyStage2AndBuildStage3(
    const PairingMessage &stage1,
    const PairingMessage &stage2
) {
    const int salt = findSalt(stage1, stage2);
    if (salt < 0) {
        // No matching salt found, return a zeroed message as a safe failure indicator
        // (embedded builds typically run with exceptions disabled).
        return PairingMessage(0x00, 0ULL, 0U, 0U);
    }

    uint32_t ourLo;
    uint32_t ourHi;
    timestampHalvesBe(stage1.timestamp, ourLo, ourHi);

    uint32_t camLo;
    uint32_t camHi;
    timestampHalvesBe(stage2.timestamp, camLo, camHi);

    const uint32_t blocks[] = {
        SALTS[salt][0], SALTS[salt][1],
        ourLo, ourHi,
        camLo, camHi
    };

    const BlowfishHasher::HashResult result = hasher.hash(blocks, 6);

    return PairingMessage(
        0x03,
        stage1.timestamp,
        reverseBytesUInt32(result.left),
        reverseBytesUInt32(result.right)
    );
}

void NikonPairingEngine::extractSerial(const PairingMessage &stage4, char *serial) {
    uint8_t encoded[PairingMessage::SIZE];
    stage4.encode(encoded);

    for (size_t i = 0; i < 8; ++i) {
        serial[i] = static_cast<char>(encoded[i + 9]);
    }
    serial[8] = '\0';
}

uint32_t NikonPairingEngine::generateDeviceId() {
    // First byte on the wire must be 0x01. On a little-endian uint32 that means the LSB.
    const uint32_t rnd = randomGenerator.nextUInt32();
    return (rnd & 0xFFFFFF00U) | 0x01U;
}

uint32_t NikonPairingEngine::generateNonce() {
    return randomGenerator.nextUInt32();
}

int NikonPairingEngine::findSalt(
    const PairingMessage &stage1,
    const PairingMessage &stage2
) {
    uint32_t camLo;
    uint32_t camHi;
    timestampHalvesBe(stage2.timestamp, camLo, camHi);

    uint32_t ourLo;
    uint32_t ourHi;
    timestampHalvesBe(stage1.timestamp, ourLo, ourHi);

    const uint32_t camDeviceBe = reverseBytesUInt32(stage2.device);
    const uint32_t camNonceBe = reverseBytesUInt32(stage2.nonce);

    for (size_t i = 0; i < SALT_COUNT; ++i) {
        const uint32_t blocks[] = {
            SALTS[i][0], SALTS[i][1],
            camLo, camHi,
            ourLo, ourHi
        };

        const BlowfishHasher::HashResult result = hasher.hash(blocks, 6);
        if (result.left == camDeviceBe && result.right == camNonceBe) {
            return static_cast<int>(i);
        }
    }

    return -1;
}

void NikonPairingEngine::timestampHalvesBe(
    const uint64_t timestamp,
    uint32_t &lo,
    uint32_t &hi
) {
    lo = reverseBytesUInt32(static_cast<uint32_t>(timestamp & 0xFFFFFFFFULL));
    hi = reverseBytesUInt32(static_cast<uint32_t>((timestamp >> 32) & 0xFFFFFFFFULL));
}

uint32_t NikonPairingEngine::reverseBytesUInt32(const uint32_t value) {
    return ((value & 0x000000FFU) << 24) |
           ((value & 0x0000FF00U) << 8) |
           ((value & 0x00FF0000U) >> 8) |
           ((value & 0xFF000000U) >> 24);
}
