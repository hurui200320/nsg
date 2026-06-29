#include "PairingMode.h"

#include <Arduino.h>
#include <M5Unified.h>

#include <cstring>
#include <string>
#include <vector>

#include "../common/ScannedCamera.h"
#include "ClassicBT.h"
#include "Config.h"
#include "Logging.h"
#include "Utils.h"

PairingMode::PairingMode() : scanner(nullptr), pClient(nullptr) {}

void PairingMode::setup() {
    BootMode::initBLE();

    scanner = new PairingScanner();
    scanner->startScanning();
}

// TODO: clean up these
std::vector<ScannedCamera> cameraList;
bool selectedCamera = false;
size_t selectedCameraIdx = 0;

void PairingMode::loop() {
    ScannedCamera camera;
    while (xQueueReceive(scanner->scanResultQueue, &camera, (TickType_t)0)) {
        auto deviceName = std::string(camera.name);
        auto deviceAddr = BLEAddress(camera.addr);
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
            Logging::info("BLEScanCallback", "Found " + String(deviceName.c_str()) + ", addr=" + deviceAddr.toString());
        }
    }

    // TODO: show list on screen?
    // TODO: select one camera

    // TODO: assuming we select the first camera in list
    if (!selectedCamera && cameraList.size() > 0) {
        scanner->stopScanning();
        selectedCameraIdx = 0;
        selectedCamera = true;
        Logging::info("PairingMode::loop", String("Pairing with ") + cameraList[selectedCameraIdx].name);
    }

    // TODO: need to ensure only execute once
    if (selectedCamera) {
        camera = cameraList[selectedCameraIdx];
        auto cameraName = std::string(camera.name);
        auto cameraAddr = BLEAddress(camera.addr);
        // perform BLE handshake
        pClient = new NikonBLEClient();
        if (!pClient->doHandshake(cameraAddr, camera.addrType)) {
            Logging::fatal("loop", "failed to perform handshake");
        }
        Logging::info("loop", "Disconnecting BLE connection");
        pClient->disconnect();
        // TODO: test if we can bring up classic BT while keeping BLE stack
        // delete pClient;
        // pClient = nullptr;

        // start classic BT pairing
        auto classicBT = new ClassicBT(cameraName);
        // TODO hardcoded to search for 1 minutes
        if (classicBT->searchAndInitiatePair(60000)) {
            auto code = classicBT->getPairCode();
            Logging::info("PairingMode::bondClassic", "Pair code: " + String(code));
            // TODO: show code on screen and let user confirm
            if (classicBT->confirmPairCode(true)) {
                Logging::info("PairingMode::bondClassic", "Classic BT bond established");
                // add the saved device into list
                Logging::info("loop", "Saving paired camera info...");
                SavedCameraInfo cameraInfo(String(cameraName.c_str()), pClient->getDevice(), pClient->getNonce());
                Config::addToSavedCameras(cameraInfo);
            } else {
                Logging::error("PairingMode::bondClassic", "failed to confirm pair code");
            }
        } else {
            Logging::fatal("PairingMode::bondClassic", "failed to search and initiate pair");
        }
        delete classicBT;
        classicBT = nullptr;
        delete pClient;
        // reboot anyway
        Logging::info("loop", "rebooting...");
        ESP.restart();
    }
}
