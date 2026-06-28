#include "NormalMode.h"

#include <vector>
#include <M5Unified.h>

#include "../common/NikonBLEClient.h"
#include "Config.h"
#include "Logging.h"
#include "PairedScanner.h"

NormalMode::NormalMode() : scanner(nullptr), connectedCameras() {}

void NormalMode::setup() {
    auto savedCameras = Config::getSavedCameras();
    connectedCameras.reserve(savedCameras.size());
    for (size_t i = 0; i < savedCameras.size(); i++) {
        auto saved = savedCameras[i];
        ConnectedCamera connected(saved);
        connectedCameras.push_back(connected);
    }

    BootMode::initBLE();
    scanner = new PairedScanner();
    if (!scanner->startScanning()) {
        Logging::fatal("NormalSetup", "failed to start BLE scanning");
    }
}

void NormalMode::loop() {
    ScannedCamera scanned;
    bool scanStopped = false;
    while (xQueueReceive(scanner->scanResultQueue, &scanned, (TickType_t)0)) {
        // search for connected, if it is advertising, then it's disconnected
        // we need to (re)initialize the BLE client
        for (auto& item : connectedCameras) {
            if (item.info.bleName == scanned.name && item.info.device == scanned.device) {
                if (item.pClient != nullptr && !item.pClient->isConnnected()) {
                    // disconnected, kill current client and restart
                    item.pClient->disconnect();
                    delete item.pClient;
                    item.pClient = nullptr;
                    item.lastBroadcastMillis = millis();
                }
                if (item.pClient == nullptr) {
                    item.pClient = new NikonBLEClient(item.info.device, item.info.nonce);
                    if (!scanStopped) {
                        // stop scanning to free up the attenna
                        scanner->stopScanning();
                        scanStopped = true;
                    }
                    auto bleAddr = BLEAddress(scanned.addr);
                    if (!item.pClient->doHandshake(bleAddr, scanned.addrType)) {
                        Logging::error("NormalLoop", "Failed to reconnect to " + bleAddr.toString() + "due to handshake failure");
                    } else {
                        Logging::error("NormalLoop", "BLE connected to " + bleAddr.toString());
                    }
                }
            }
        }
    }
    // TODO: loop through clients, update them
    for (auto& item : connectedCameras) {
        if (millis() - item.lastBroadcastMillis < 15000) continue;
        if (item.pClient == nullptr) continue;
        if (!item.pClient->isConnnected()) continue;
        // TODO: send time and geo
        // auto dateTime = M5.Rtc.getDateTime();
        // sprintf( dateTime.date.year, dateTime.date.month, dateTime.date.date, dateTime.date.weekDay,
                // dateTime.time.hours, dateTime.time.minutes, dateTime.time.seconds);
    }

    // TODO: RTC?

    // if scan stopped, resume scan
    if (scanStopped) {
        // restart scanning
        if (!scanner->startScanning()) {
            Logging::fatal("NormalSetup", "failed to start BLE scanning");
        }
    }
}
