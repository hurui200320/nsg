/**
 * ESP32 hardware random generator.
 *
 * Uses esp_random() which returns cryptographically secure random values
 * sourced from the Wi-Fi/BT noise.
 *
 * This implementation is only available on ESP32.
 */

#ifndef ESP32_RANDOM_GENERATOR_H
#define ESP32_RANDOM_GENERATOR_H


#include "RandomGenerator.h"

class Esp32RandomGenerator : public RandomGenerator {
public:
    uint32_t nextUInt32() override;
    uint64_t nextUInt64() override;
};

#endif // ESP32_RANDOM_GENERATOR_H
