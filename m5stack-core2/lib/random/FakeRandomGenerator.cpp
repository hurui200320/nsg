#include "FakeRandomGenerator.h"

FakeRandomGenerator::FakeRandomGenerator() : values(), index(0) {}

FakeRandomGenerator::FakeRandomGenerator(const std::vector<uint32_t>& sequence)
    : values(sequence), index(0) {}

void FakeRandomGenerator::setSequence(const std::vector<uint32_t>& sequence) {
    values = sequence;
    index = 0;
}

void FakeRandomGenerator::reset() {
    index = 0;
}

uint32_t FakeRandomGenerator::nextUInt32() {
    if (values.empty()) {
        return 0;
    }
    const uint32_t value = values[index % values.size()];
    ++index;
    return value;
}

uint64_t FakeRandomGenerator::nextUInt64() {
    const uint64_t lo = nextUInt32();
    const uint64_t hi = nextUInt32();
    return (hi << 32) | lo;
}
