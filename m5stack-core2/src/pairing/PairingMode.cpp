#include "PairingMode.h"

#include <Arduino.h>
#include <BLEDevice.h>

#include <string>
#include <vector>
#include <cstring>

#include "Config.h"
#include "Logging.h"
#include "NikonUUID.h"
#include "Utils.h"
#include "PairingScanner.h"
#include "PairingModels.h"

PairingMode::PairingMode() {
}

PairingScanner* scanner;

void PairingMode::setup() {
    BootMode::initBLE();
    scanner = new PairingScanner();
    scanner->startScanning();
}

std::vector<Camera> cameraList;
bool selectedCamera = false;
size_t selectedCameraIdx = 0;

void PairingMode::loop() {
    Camera camera;
    while (xQueueReceive(scanner->scanResultQueue, &camera, (TickType_t)0)) {
        auto deviceName = std::string(camera.name);
        auto deviceAddr = std::string(camera.addr);
        bool dup = false;
        for (size_t i = 0; i < cameraList.size(); i++) {
            auto item = cameraList[i];
            if (memcmp(item.addr, camera.addr, sizeof(item.addr)) == 0) {
                dup = true;
                break;
            }
        }
        if (!dup) {
            cameraList.push_back(camera);
            Logging::info("BLEScanCallback",
                          "Found " + deviceName + ", addr=" + deviceAddr);
        }
    }

    // TODO: show list on screen?
    // TODO: select one camera

    // TODO: assuming we select the first camera in list
    if (!selectedCamera && cameraList.size() > 0) {
        scanner->stopScanning();
        selectedCameraIdx = 0;
        selectedCamera = true;
        Logging::info("PairingMode::loop", "Pairing with " + std::string(cameraList[selectedCameraIdx].name));
    }
}
