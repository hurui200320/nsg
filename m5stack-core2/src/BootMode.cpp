#include "BootMode.h"

#include <BLEDevice.h>

#include "Config.h"
#include "Logging.h"
#include "Utils.h"

void BootMode::initBLE() {
    auto id = Config::getOrGenerateId();
    auto idStr = Utils::uint32ToLittleEndianHexString(id);
    auto bleDeviceName = "nsg-" + idStr;
    Logging::info("BootMode::initBLE", "BLE device name: " + bleDeviceName);
    // enable BLE
    BLEDevice::init(bleDeviceName);
}