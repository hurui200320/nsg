#include "PairingMode.h"

#include <Arduino.h>

#include <cstring>

#include "Config.h"
#include "Logging.h"
#include "Utils.h"
#include "common/StatusLED.h"

PairingMode::PairingMode() : state(State::SCANNING), scanner(nullptr), pClient(nullptr), classicBT(nullptr), cameraList(), selectedCameraIdx(0) {}

PairingMode::~PairingMode() {
    if (scanner != nullptr) {
        scanner->stopScanning();
    }
}

void PairingMode::setup() {
    scanner.reset(new NikonBLEScanner(NikonBLEScannerMode::NEW_DEVICE));
    if (!scanner->startScanning()) {
        NSG_LOG_FATAL("PairingMode::setup", "failed to start BLE scanning");
    }
    selectedCameraIdx = 0;
}

void PairingMode::loop() {
    // Scanning: show scan results on screen and wait user to select
    // BLE_HANDSHAKE: after user select, do BLE handshake
    // PAIRING: after BLE handshake success, do classic BT pairing
    // SHOW_CODE: show code on screen and wait user to confirm
    // CODE_CONFIRM: user confirmed code, wait pairing result
    // SUCCESS: after pairing success, save camera info and reboot
    // FAIL: if any of the stage failed, jump to here and loop, user need to manually reset
    // status LED: R on = pairing mode; B on from handshake until pairing
    // finishes; B blinks at 1 Hz while waiting for the user to confirm the
    // code on the camera; all channels on = fatal failure, power cycle required
    if (state == State::FAIL) {
        statusLed.setColor(STATUS_LED_ON, STATUS_LED_ON, STATUS_LED_ON);
    } else if (state == State::CODE_CONFIRM) {
        const bool blinkOn = (millis() / 500) % 2 == 0;
        statusLed.setColor(STATUS_LED_ON, STATUS_LED_OFF, blinkOn ? STATUS_LED_ON : STATUS_LED_OFF);
    } else {
        const bool pairingStarted = state != State::SCANNING;
        statusLed.setColor(STATUS_LED_ON, STATUS_LED_OFF, pairingStarted ? STATUS_LED_ON : STATUS_LED_OFF);
    }
    switch (state) {
        case State::SCANNING:
            handleScanResults();
            break;
        case State::BLE_HANDSHAKE:
            doBLEHandshake();
            break;
        case State::PAIRING:
            startPairingFlow();
            break;
        case State::SHOW_CODE:
            showCodeAndWaitConfirm();
            break;
        case State::CODE_CONFIRM:
            waitPairingResult();
            break;
        case State::SUCCESS:
            saveAndReboot();
            break;
        case State::FAIL:
            // release resouces
            if (classicBT) classicBT.reset();
            if (pClient) pClient.reset();
            if (scanner) scanner.reset();
            NSG_LOG_ERROR("PairingMode::loop", "Failed to pair, please manually reset...");
            delay(10);
            break;
    }
    // prevent watchdog goes crazy
    yield();
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
            NSG_LOG_INFO("PairingMode::handleScanResults", "Found %s, addr=%s", deviceName.c_str(), deviceAddr.toString().c_str());
        }
        // prevent blocking
        yield();
    }

    // automatically select first camera found
    if (!cameraList.empty()) {
        NSG_LOG_INFO("PairingMode::handleScanResults", "Automatically select first camera");
        selectedCameraIdx = 0;
        scanner->stopScanning();
        state = State::BLE_HANDSHAKE;
        NSG_LOG_INFO("PairingMode::handleScanResults", "selecting %s", cameraList[selectedCameraIdx].name);
    }
}

void PairingMode::doBLEHandshake() {
    const ScannedCamera& camera = cameraList[selectedCameraIdx];
    const BLEAddress cameraAddr(const_cast<uint8_t*>(camera.addr), camera.addrType);

    NSG_LOG_INFO("PairingMode::doBLEHandshake", "Start BLE handshake with %s", camera.name);

    // Perform BLE handshake.
    pClient.reset(new NikonBLEClient(rnd));
    if (!pClient->doHandshake(cameraAddr, camera.addrType)) {
        state = State::FAIL;
        NSG_LOG_ERROR("PairingMode::doBLEHandshake", "BLE Handshake failed");
        NSG_LOG_WARN("PairingMode::doBLEHandshake", "BLE handshake with %s failed!", camera.name);
    } else {
        state = State::PAIRING;
        NSG_LOG_INFO("PairingMode::doBLEHandshake", "BLE Handshake success");
        NSG_LOG_INFO("PairingMode::doBLEHandshake", "BLE handshake with %s succeeded!", camera.name);
    }
    NSG_LOG_INFO("PairingMode::doBLEHandshake", "Disconnecting BLE connection");
    pClient->disconnect();
}

void PairingMode::startPairingFlow() {
    const ScannedCamera& camera = cameraList[selectedCameraIdx];
    const std::string cameraName(camera.name);

    NSG_LOG_INFO("PairingMode::startPairingFlow", "Start classic BT pairing with %s", camera.name);

    // Start Classic Bluetooth pairing.
    classicBT.reset(new ClassicBT(cameraName));
    // TODO: blocking? will it hurt anything?
    if (!classicBT->searchAndInitiatePair(NIKON_BT_SEARCH_TIME_MS)) {
        state = State::FAIL;
        NSG_LOG_ERROR("PairingMode::startPairingFlow", "Failed to search and initiate pairing");
        NSG_LOG_WARN("PairingMode::startPairingFlow", "Failed to initiate classic BT pairing with %s", camera.name);
    } else {
        state = State::SHOW_CODE;
        NSG_LOG_INFO("PairingMode::startPairingFlow", "Initiated pairing");
        NSG_LOG_INFO("PairingMode::startPairingFlow", "Successfully initiated classic BT pairing with %s", camera.name);
    }
}

void PairingMode::showCodeAndWaitConfirm() {
    if (!classicBT->isPairCodeReady()) {
        delay(100);
        return;
    }
    NSG_LOG_INFO("PairingMode::showCodeAndWaitConfirm", "Classic BT pairing code: %06lu, auto confirm...", (unsigned long)classicBT->getPairCode());
    classicBT->confirmPairCode(true);
    timeAfterPairSuccess = 0;
    state = State::CODE_CONFIRM;
}

void PairingMode::waitPairingResult() {
    if (classicBT->isPairingDone(NIKON_BT_PAIR_TIMEOUT_MS)) {  // pair done, or timeout
        const bool isPairingSuccess = classicBT->isPairingSuccess();
        if (isPairingSuccess) {  // pairing success
            if (timeAfterPairSuccess == 0) {
                // set time and start waiting
                timeAfterPairSuccess = millis();
                NSG_LOG_INFO("PairingMode::waitPairingResult", "Waiting %d ms for camera to make connection...", NIKON_BT_AFTER_PAIR_TIME_MS);
            }
            // wait extra time for camera to make the connection
            if (millis() - timeAfterPairSuccess < NIKON_BT_AFTER_PAIR_TIME_MS) {
                delay(50);
                return;  // keep waiting
            } else {
                NSG_LOG_INFO("PairingMode::waitPairingResult", "Finished classic BT pairing");
                NSG_LOG_INFO("PairingMode::waitPairingResult", "Classic BT bond established");
                state = State::SUCCESS;
            }
        } else {  // pairing not success
            state = State::FAIL;
            NSG_LOG_ERROR("PairingMode::waitPairingResult", "Pairing failed");
            NSG_LOG_INFO("PairingMode::waitPairingResult", "Finished classic BT pairing");
        }
    } else {  // pairing in progress
        delay(50);
    }
}

void PairingMode::saveAndReboot() {
    const ScannedCamera& camera = cameraList[selectedCameraIdx];
    NSG_LOG_INFO("PairingMode::saveAndReboot", "Saving paired camera info...");
    SavedCameraInfo cameraInfo(String(camera.name), pClient->getDevice(), pClient->getNonce());
    NSG_LOG_INFO("PairingMode::saveAndReboot", "Successfully paired with %s", cameraInfo.bleName.c_str());
    Config::addToSavedCameras(cameraInfo);

    // Clean up before reboot.
    classicBT.reset();
    pClient.reset();
    scanner.reset();
    NSG_LOG_INFO("PairingMode::saveAndReboot", "rebooting...");
    ESP.restart();
}
