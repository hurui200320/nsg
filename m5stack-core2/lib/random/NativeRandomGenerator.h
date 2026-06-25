/**
 * Native random generator for unit testing.
 *
 * Uses std::random_device as a secure source of non-deterministic random
 * values. Falls back to std::mt19937 if std::random_device is not available.
 *
 * This implementation is only available on non-ESP32 platforms.
 */

#ifndef NATIVE_RANDOM_GENERATOR_H
#define NATIVE_RANDOM_GENERATOR_H

#ifndef ESP32

#include <random>

#include "RandomGenerator.h"

class NativeRandomGenerator : public RandomGenerator {
public:
    NativeRandomGenerator();

    uint32_t random_uint32() override;
    uint64_t random_uint64() override;

private:
    std::random_device rd;
    std::mt19937 fallback;
    std::uniform_int_distribution<uint32_t> dist32;
    std::uniform_int_distribution<uint64_t> dist64;
};

#endif // !ESP32

#endif // NATIVE_RANDOM_GENERATOR_H
