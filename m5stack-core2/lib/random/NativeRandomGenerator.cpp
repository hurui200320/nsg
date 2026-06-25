#include "NativeRandomGenerator.h"

#ifndef ESP32

NativeRandomGenerator::NativeRandomGenerator()
    : fallback(rd()), dist32(0, UINT32_MAX), dist64(0, UINT64_MAX) {
}

uint32_t NativeRandomGenerator::random_uint32() {
    if (rd.entropy() > 0) {
        return dist32(rd);
    }
    return dist32(fallback);
}

uint64_t NativeRandomGenerator::random_uint64() {
    if (rd.entropy() > 0) {
        return dist64(rd);
    }
    return dist64(fallback);
}

#endif // !ESP32
