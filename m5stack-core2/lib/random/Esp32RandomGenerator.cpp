#include "Esp32RandomGenerator.h"

#ifdef ESP32

#include <esp_random.h>

uint32_t Esp32RandomGenerator::random_uint32() {
    return esp_random();
}

uint64_t Esp32RandomGenerator::random_uint64() {
    const uint32_t lo = esp_random();
    const uint32_t hi = esp_random();
    return (static_cast<uint64_t>(hi) << 32) | static_cast<uint64_t>(lo);
}

#endif // ESP32
