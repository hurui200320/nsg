#include "BlowfishHasher.h"

static const uint8_t KEY[] = {
    0xFF, 0xFF, 0xAA, 0x55,
    0x11, 0x22, 0x33, 0x00
};

BlowfishHasher::BlowfishHasher() {
    bfish_init(&bf, KEY, sizeof(KEY));
}

BlowfishHasher::HashResult BlowfishHasher::hash(const uint32_t *blocks, size_t count) {
    if (count % 2 != 0 || blocks == nullptr) {
        // Kotlin version throws IllegalArgumentException on odd counts.
        // Embedded builds typically run with exceptions disabled, so return
        // an explicitly invalid result.
        return {0, 0, false};
    }

    uint32_t left = 0x01020304;
    uint32_t right = 0x05060708;

    for (size_t i = 0; i < count; i += 2) {
        uint32_t inL = blocks[i] ^ left;
        uint32_t inR = blocks[i + 1] ^ right;

        bfblk_t blk;
        blk.hi = inL;
        blk.lo = inR;
        bfish_enblock(&bf, &blk);

        left = blk.hi;
        right = blk.lo;
    }

    return {left, right, true};
}
