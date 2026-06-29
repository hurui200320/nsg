#include "PairingMode.h"

#include <Arduino.h>
#include <M5Unified.h>

#include <cstring>

#include "Config.h"
#include "Logging.h"
#include "Utils.h"

PairingMode::PairingMode() : state(State::SCANNING), scanner(nullptr), pClient(nullptr), classicBT(nullptr), cameraList(), selectedCameraIdx(0) {}

PairingMode::~PairingMode() {
    if (scanner != nullptr) {
        scanner->stopScanning();
    }
}

void PairingMode::setup() {
    BootMode::initBLE(rnd);

    scanner.reset(new PairingScanner());
    scanner->startScanning();
}

void PairingMode::loop() {
    switch (state) {
        case State::SCANNING:
            handleScanResults();
            selectFirstCamera();
            break;

        case State::PAIRING:
            runPairingFlow();
            break;

        case State::DONE:
            // Clean up before reboot.
            classicBT.reset();
            pClient.reset();
            NSG_LOG_INFO("PairingMode::loop", "rebooting...");
            ESP.restart();
            break;
    }
}

void PairingMode::handleScanResults() {
    ScannedCamera camera;
    while (xQueueReceive(scanner->scanResultQueue, &camera, (TickType_t)0)) {
        auto deviceName = std::string(camera.name);
        auto deviceAddr = BLEAddress(camera.addr);
        bool dup = false;
        for (const auto& item : cameraList) {
            if (memcmp(item.addr, camera.addr, sizeof(item.addr)) == 0) {
                dup = true;
                break;
            }
        }
        if (!dup) {
            cameraList.push_back(camera);
            NSG_LOG_INFO("BLEScanCallback", "Found %s, addr=%s", deviceName.c_str(), deviceAddr.toString().c_str());
        }
    }
}

void PairingMode::selectFirstCamera() {
    // TODO: show list on screen and let the user select a camera.
    // For now, pair with the first discovered camera.
    if (!cameraList.empty()) {
        scanner->stopScanning();
        selectedCameraIdx = 0;
        state = State::PAIRING;
        NSG_LOG_INFO("PairingMode::selectFirstCamera", "Pairing with %s", cameraList[selectedCameraIdx].name);
    }
}

void PairingMode::runPairingFlow() {
    state = State::DONE;

    const ScannedCamera& camera = cameraList[selectedCameraIdx];
    const std::string cameraName(camera.name);
    const BLEAddress cameraAddr(const_cast<uint8_t*>(camera.addr), camera.addrType);

    // Perform BLE handshake.
    pClient.reset(new NikonBLEClient(rnd));
    if (!pClient->doHandshake(cameraAddr, camera.addrType)) {
        NSG_LOG_FATAL("PairingMode::runPairingFlow", "failed to perform handshake");
    }
    NSG_LOG_INFO("PairingMode::runPairingFlow", "Disconnecting BLE connection");
    pClient->disconnect();

    // Start Classic Bluetooth pairing.
    classicBT.reset(new ClassicBT(cameraName));
    // TODO: hardcoded to search for 1 minute.
    if (!classicBT->searchAndInitiatePair(60000)) {
        NSG_LOG_FATAL("PairingMode::runPairingFlow", "failed to search and initiate pair");
    }

    const uint32_t code = classicBT->getPairCode();
    NSG_LOG_INFO("PairingMode::runPairingFlow", "Pair code: %06u", code);
    // TODO: show code on screen and let user confirm.
    if (!classicBT->confirmPairCode(true)) {
        NSG_LOG_ERROR("PairingMode::runPairingFlow", "failed to confirm pair code");
        return;
    }
    NSG_LOG_INFO("PairingMode::runPairingFlow", "Classic BT bond established");

    NSG_LOG_INFO("PairingMode::runPairingFlow", "Saving paired camera info...");
    SavedCameraInfo cameraInfo(String(cameraName.c_str()), pClient->getDevice(), pClient->getNonce());
    Config::addToSavedCameras(cameraInfo);
}
