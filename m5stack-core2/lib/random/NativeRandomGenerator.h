/**
 * Native random generator for unit testing.
 *
 * Uses std::random_device as a source of non-deterministic random values.
 * If std::random_device is deterministic on the host platform the output
 * will be predictable, which is acceptable for the native test target.
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

    uint32_t nextUInt32() override;
    uint64_t nextUInt64() override;

private:
    std::random_device rd;
    std::uniform_int_distribution<uint32_t> dist32;
    std::uniform_int_distribution<uint64_t> dist64;
};

#endif // !ESP32

#endif // NATIVE_RANDOM_GENERATOR_H
