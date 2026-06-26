#include "NativeRandomGenerator.h"

#ifndef ESP32

NativeRandomGenerator::NativeRandomGenerator()
    : dist32(0, UINT32_MAX), dist64(0, UINT64_MAX) {
}

uint32_t NativeRandomGenerator::nextUInt32() {
    return dist32(rd);
}

uint64_t NativeRandomGenerator::nextUInt64() {
    return dist64(rd);
}

#endif // !ESP32
