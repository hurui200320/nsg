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

NikonPairingEngine::NikonPairingEngine(RandomGenerator &random_generator, BlowfishHasher &hasher)
    : random_generator(random_generator), hasher(hasher) {
}

PairingMessage NikonPairingEngine::create_stage1(
    const uint32_t *saved_device,
    const uint32_t *saved_nonce
) {
    const uint64_t timestamp = random_generator.random_uint64();
    const uint32_t device = saved_device != nullptr ? *saved_device : generate_device_id();
    const uint32_t nonce = saved_nonce != nullptr ? *saved_nonce : generate_nonce();

    return PairingMessage(0x01, timestamp, device, nonce);
}

PairingMessage NikonPairingEngine::verify_stage2_and_build_stage3(
    const PairingMessage &stage1,
    const PairingMessage &stage2
) {
    const int salt = find_salt(stage1, stage2);
    if (salt < 0) {
        // No matching salt found, return a zeroed message as a safe failure indicator
        // (embedded builds typically run with exceptions disabled).
        return PairingMessage(0x00, 0ULL, 0U, 0U);
    }

    uint32_t our_lo;
    uint32_t our_hi;
    timestamp_halves_be(stage1.timestamp, our_lo, our_hi);

    uint32_t cam_lo;
    uint32_t cam_hi;
    timestamp_halves_be(stage2.timestamp, cam_lo, cam_hi);

    const uint32_t blocks[] = {
        SALTS[salt][0], SALTS[salt][1],
        our_lo, our_hi,
        cam_lo, cam_hi
    };

    const BlowfishHasher::HashResult result = hasher.hash(blocks, 6);

    return PairingMessage(
        0x03,
        stage1.timestamp,
        reverse_bytes_uint32(result.left),
        reverse_bytes_uint32(result.right)
    );
}

void NikonPairingEngine::extract_serial(const PairingMessage &stage4, char *serial) {
    uint8_t encoded[PairingMessage::SIZE];
    stage4.encode(encoded);

    for (size_t i = 0; i < 8; ++i) {
        serial[i] = static_cast<char>(encoded[i + 9]);
    }
    serial[8] = '\0';
}

uint32_t NikonPairingEngine::generate_device_id() {
    // First byte on the wire must be 0x01. On a little-endian uint32 that means the LSB.
    const uint32_t rnd = random_generator.random_uint32();
    return (rnd & 0xFFFFFF00U) | 0x01U;
}

uint32_t NikonPairingEngine::generate_nonce() {
    return random_generator.random_uint32();
}

int NikonPairingEngine::find_salt(
    const PairingMessage &stage1,
    const PairingMessage &stage2
) {
    uint32_t cam_lo;
    uint32_t cam_hi;
    timestamp_halves_be(stage2.timestamp, cam_lo, cam_hi);

    uint32_t our_lo;
    uint32_t our_hi;
    timestamp_halves_be(stage1.timestamp, our_lo, our_hi);

    const uint32_t cam_device_be = reverse_bytes_uint32(stage2.device);
    const uint32_t cam_nonce_be = reverse_bytes_uint32(stage2.nonce);

    for (size_t i = 0; i < SALT_COUNT; ++i) {
        const uint32_t blocks[] = {
            SALTS[i][0], SALTS[i][1],
            cam_lo, cam_hi,
            our_lo, our_hi
        };

        const BlowfishHasher::HashResult result = hasher.hash(blocks, 6);
        if (result.left == cam_device_be && result.right == cam_nonce_be) {
            return static_cast<int>(i);
        }
    }

    return -1;
}

void NikonPairingEngine::timestamp_halves_be(
    const uint64_t timestamp,
    uint32_t &lo,
    uint32_t &hi
) {
    lo = reverse_bytes_uint32(static_cast<uint32_t>(timestamp & 0xFFFFFFFFULL));
    hi = reverse_bytes_uint32(static_cast<uint32_t>((timestamp >> 32) & 0xFFFFFFFFULL));
}

uint32_t NikonPairingEngine::reverse_bytes_uint32(const uint32_t value) {
    return ((value & 0x000000FFU) << 24) |
           ((value & 0x0000FF00U) << 8) |
           ((value & 0x00FF0000U) >> 8) |
           ((value & 0xFF000000U) >> 24);
}
