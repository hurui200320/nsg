/**
 * C++ port of BlowfishHasher from kotlin-poc.
 *
 * Implements the custom Blowfish-based hash used in the Nikon pairing handshake.
 *
 * The underlying block cipher is standard Blowfish in ECB mode with no padding.
 * The 8-byte key is:
 *     FF FF AA 55 11 22 33 00
 *
 * Hash input blocks are treated as big-endian 32-bit words.
 */

#ifndef BLOWFISH_HASHER_H
#define BLOWFISH_HASHER_H

#include <cstddef>
#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

#include <blowfish.h>

#ifdef __cplusplus
}
#endif

class BlowfishHasher {
public:
    struct HashResult {
        uint32_t left;
        uint32_t right;
    };

    BlowfishHasher();

    /**
     * Hashes an array of 32-bit big-endian words.
     *
     * [blocks] must contain an even number of words.
     * Returns the final (left, right) pair.
     */
    HashResult hash(const uint32_t *blocks, size_t count);

private:
    bfish_t bf;
};

#endif // BLOWFISH_HASHER_H
