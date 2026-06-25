/**
 * Random number generator interface for the Nikon pairing protocol.
 *
 * The protocol needs cryptographically secure random uint32 and uint64 values.
 * Different platforms (native test vs. ESP32) provide different secure RNGs,
 * so the engine depends on this interface rather than a concrete implementation.
 */

#ifndef RANDOM_GENERATOR_H
#define RANDOM_GENERATOR_H

#include <cstdint>

class RandomGenerator {
public:
    virtual ~RandomGenerator() = default;

    virtual uint32_t random_uint32() = 0;

    virtual uint64_t random_uint64() = 0;
};

#endif // RANDOM_GENERATOR_H
