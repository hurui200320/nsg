#include "Config.h"

#include <Preferences.h>

#include "Esp32RandomGenerator.h"
#include "Logging.h"

uint32_t Config::getOrGenerateId() {
    Preferences nvs;
    if (!nvs.begin("nsg", false)) {
        Logging::fatal("Config", "Failed to open NVS");
    }

    auto result = nvs.getUInt("id", 0);
    while (result == 0) {
        Esp32RandomGenerator generator;
        result = generator.nextUInt32();
        nvs.putUInt("id", result);
    }

    nvs.end();
    return result;
}
