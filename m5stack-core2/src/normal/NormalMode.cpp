#include "NormalMode.h"

#include <M5Unified.h>

#include <vector>

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

    // currently do not need screen
    M5.Display.setBrightness(0);
}

void NormalMode::loop() {
    ScannedCamera scanned;
    bool scanStopped = false;
    while (xQueueReceive(scanner->scanResultQueue, &scanned, (TickType_t)0)) {
        // search for connected, if it is advertising, then it's disconnected
        // we need to (re)initialize the BLE client
        // TODO: how do we know the max number of BLE connection?
        for (auto& item : connectedCameras) {
            if (item.info.bleName == scanned.name && item.info.device == scanned.device) {
                if (item.pClient != nullptr && !item.pClient->isConnected()) {
                    // disconnected, kill current client and restart
                    item.pClient->disconnect();
                    delete item.pClient;
                    item.pClient = nullptr;
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
                        Logging::info("NormalLoop", "BLE connected to " + bleAddr.toString());
                        item.lastBroadcastMillis = 0;
                    }
                }
            }
        }
    }

    // TODO: loop through clients, update them
    TimeMessage timeMessage(0, 0, 0, 0, 0, 0, 0, 0, 0);
    for (auto& item : connectedCameras) {
        if (millis() - item.lastBroadcastMillis < 15000) continue;
        if (item.pClient == nullptr) continue;
        if (!item.pClient->isConnected()) continue;
        // stop scanning to free up the attenna
        if (!scanStopped) {
            scanner->stopScanning();
            scanStopped = true;
        }
        // Start sending payload
        Logging::info("NormalLoop", "Sending TIME payload to " + item.info.bleName + "...");
        updateTimeMessageWithRTC(timeMessage);
        if (!item.pClient->sendTimePayload(timeMessage)) {
            Logging::warn("NormalLoop", "Failed to send TIME payload to " + item.info.bleName);
            item.pClient->disconnect();
        }
        Logging::info("NormalLoop", "Sending GEO payload to " + item.info.bleName + "...");
        // TODO: hook up GPS
        auto geoMessage = generateGeoMessage(0.0, 0.0, 1234, 10, 1);
        if (!item.pClient->sendGeoPayload(geoMessage)) {
            Logging::warn("NormalLoop", "Failed to send GEO payload to " + item.info.bleName);
            item.pClient->disconnect();
        }

        // update broadcast time
        item.lastBroadcastMillis = millis();
    }

    // if scan stopped, resume scan
    if (scanStopped) {
        // restart scanning
        if (!scanner->startScanning()) {
            Logging::fatal("NormalSetup", "failed to start BLE scanning");
        }
    }
}

void NormalMode::updateTimeMessageWithRTC(TimeMessage& message) {
    auto datetime = M5.Rtc.getDateTime();
    // here is the UTC time
    message.year = datetime.date.year;
    message.month = datetime.date.month;
    message.day = datetime.date.date;
    message.hour = datetime.time.hours;
    message.minute = datetime.time.minutes;
    message.second = datetime.time.seconds;
    // TODO: hardcoded timezone to UTC+8
    message.dstOffset = 0;
    message.tzOffsetHours = 8;
    message.tzOffsetMinutes = 0;
}

GeoMessage NormalMode::generateGeoMessage(double lat, double lon, int32_t altitude, uint8_t satellites, uint8_t valid) {
    auto datetime = M5.Rtc.getDateTime();
    return GeoMessage::fromDecimal(lat, lon, altitude, satellites, datetime.date.year, datetime.date.month, datetime.date.date, datetime.time.hours,
                                   datetime.time.minutes, datetime.time.seconds, 0, valid);
}
