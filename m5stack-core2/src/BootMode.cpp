#include "BootMode.h"

#include <BLEDevice.h>

#include "Config.h"
#include "Logging.h"
#include "RandomGenerator.h"
#include "Utils.h"

void BootMode::initBLE(RandomGenerator& randomGenerator) {
    const uint32_t id = Config::getOrGenerateId(randomGenerator);
    const std::string bleDeviceName = Utils::generateFullId(id);
    NSG_LOG_INFO("BootMode::initBLE", "BLE device name: %s", bleDeviceName.c_str());
    // enable BLE
    BLEDevice::init(String(bleDeviceName.c_str()));
}