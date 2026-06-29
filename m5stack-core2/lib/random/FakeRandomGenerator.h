/**
 * Deterministic random generator for unit testing.
 *
 * Returns a predefined sequence of 32-bit values. When the sequence is
 * exhausted it wraps around to the beginning. This makes pairing-engine
 * tests fully reproducible.
 */

#ifndef FAKE_RANDOM_GENERATOR_H
#define FAKE_RANDOM_GENERATOR_H

#include <cstddef>
#include <cstdint>
#include <vector>

#include "RandomGenerator.h"

class FakeRandomGenerator : public RandomGenerator {
public:
    FakeRandomGenerator();
    explicit FakeRandomGenerator(const std::vector<uint32_t>& sequence);

    void setSequence(const std::vector<uint32_t>& sequence);
    void reset();

    uint32_t nextUInt32() override;
    uint64_t nextUInt64() override;

private:
    std::vector<uint32_t> values;
    size_t index;
};

#endif // FAKE_RANDOM_GENERATOR_H
