#include "NormalMode.h"

#include <M5Unified.h>

#include "../common/NikonBLEClient.h"
#include "Config.h"
#include "Logging.h"
#include "PairedScanner.h"

NormalMode::NormalMode() : connectedCameras() {}

NormalMode::~NormalMode() {
    if (scanner) {
        scanner->stopScanning();
    }
}

void NormalMode::setup() {
    auto savedCameras = Config::getSavedCameras();
    connectedCameras.reserve(savedCameras.size());
    for (const auto& saved : savedCameras) {
        connectedCameras.emplace_back(saved);
    }

    BootMode::initBLE(rnd);
    scanner.reset(new PairedScanner());
    if (!scanner->startScanning()) {
        NSG_LOG_FATAL("NormalSetup", "failed to start BLE scanning");
    }

    // TODO: check RTC, if year < 2026, force waiting for GPS fix to update time

    // TODO: currently do not need screen
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
                if (item.pClient && !item.pClient->isConnected()) {
                    // disconnected, kill current client and restart
                    item.pClient->disconnect();
                    item.pClient.reset();
                }
                if (!item.pClient) {
                    item.pClient.reset(new NikonBLEClient(rnd, item.info.device, item.info.nonce));
                    if (!scanStopped) {
                        // stop scanning to free up the attenna
                        scanner->stopScanning();
                        scanStopped = true;
                    }
                    auto bleAddr = BLEAddress(scanned.addr);
                    if (!item.pClient->doHandshake(bleAddr, scanned.addrType)) {
                        NSG_LOG_ERROR("NormalLoop", "Failed to reconnect to %s due to handshake failure", bleAddr.toString().c_str());
                        // clean up stale client asap
                        item.pClient.reset();
                    } else {
                        NSG_LOG_INFO("NormalLoop", "BLE connected to %s", bleAddr.toString().c_str());
                        item.lastBroadcastMillis = 0;
                    }
                }
            }
        }
    }

    // loop through clients, send broadcast if interval is reached
    TimeMessage timeMessage(0, 0, 0, 0, 0, 0, 0, 0, 0);
    for (auto& item : connectedCameras) {
        if (millis() - item.lastBroadcastMillis < 15000) continue;
        if (!item.pClient) continue;
        if (!item.pClient->isConnected()) continue;
        // stop scanning to free up the attenna
        if (!scanStopped) {
            scanner->stopScanning();
            scanStopped = true;
        }
        // Start sending payload
        NSG_LOG_INFO("NormalLoop", "Sending TIME payload to %s...", item.info.bleName.c_str());
        updateTimeMessageWithRTC(timeMessage);
        if (!item.pClient->sendTimePayload(timeMessage)) {
            NSG_LOG_WARN("NormalLoop", "Failed to send TIME payload to %s", item.info.bleName.c_str());
            item.pClient->disconnect();
        }
        NSG_LOG_INFO("NormalLoop", "Sending GEO payload to %s...", item.info.bleName.c_str());
        // TODO: hook up GPS
        auto geoMessage = generateGeoMessage(0.0, 0.0, 1234, 10, 1);
        if (!item.pClient->sendGeoPayload(geoMessage)) {
            NSG_LOG_WARN("NormalLoop", "Failed to send GEO payload to %s", item.info.bleName.c_str());
            item.pClient->disconnect();
        }

        // update broadcast time
        item.lastBroadcastMillis = millis();
    }

    // if scan stopped, resume scan
    if (scanStopped) {
        // restart scanning
        if (!scanner->startScanning()) {
            NSG_LOG_FATAL("NormalSetup", "failed to start BLE scanning");
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
    // TODO: hardcoded timezone to UTC+8, maybe using build arg and default to 8?
    message.dstOffset = 0;
    message.tzOffsetHours = 8;
    message.tzOffsetMinutes = 0;
}

GeoMessage NormalMode::generateGeoMessage(double lat, double lon, int32_t altitude, uint8_t satellites, uint8_t valid) {
    auto datetime = M5.Rtc.getDateTime();
    return GeoMessage::fromDecimal(lat, lon, altitude, satellites, datetime.date.year, datetime.date.month, datetime.date.date, datetime.time.hours,
                                   datetime.time.minutes, datetime.time.seconds, 0, valid);
}
