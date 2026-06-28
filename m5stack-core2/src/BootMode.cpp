#include "BootMode.h"

#include <BLEDevice.h>

#include "Config.h"
#include "Logging.h"
#include "Utils.h"

void BootMode::initBLE() {
    auto id = Config::getOrGenerateId();
    auto bleDeviceName = String(Utils::generateFullId(id).c_str());
    Logging::info("BootMode::initBLE", "BLE device name: " + bleDeviceName);
    // enable BLE
    BLEDevice::init(bleDeviceName);
}