#include "BleWorker.h"

#include <time.h>

#include "BleRetryPolicy.h"
#include "common/NikonBLEClient.h"
#include "Config.h"
#include "GeoMessage.h"
#include "Logging.h"
#include "TimeMessage.h"

namespace {

// Fill a TIME message from an already-locked RTC read. The caller is
// responsible for having read `dt` under the BleWorker mutex.
void updateTimeMessageWithRTC(TimeMessage& message, const RtcSnapshot& dt) {
    // here is the UTC time
    message.year = dt.year;
    message.month = dt.month;
    message.day = dt.day;
    message.hour = dt.hour;
    message.minute = dt.minute;
    message.second = dt.second;
    message.dstOffset = 0;
    message.tzOffsetHours = TZ_OFFSET_HOUR;
    message.tzOffsetMinutes = 0;
}

// Read the ESP32 internal RTC (system clock, UTC).
static RtcSnapshot readSystemRTC() {
    time_t now = time(nullptr);
    struct tm t{};
    gmtime_r(&now, &t);
    return {(uint16_t)(t.tm_year + 1900), (uint8_t)(t.tm_mon + 1), (uint8_t)t.tm_mday, (uint8_t)t.tm_hour, (uint8_t)t.tm_min, (uint8_t)t.tm_sec};
}

GeoMessage generateGeoMessage(const GnssSnapshot& snap, const RtcSnapshot& dt) {
    return GeoMessage::fromDecimal(snap.lat, snap.lon, snap.altitudeMeters, snap.satellites,  //
                                   dt.year, dt.month, dt.day,                                 //
                                   dt.hour, dt.minute, dt.second, 0,                          //
                                   snap.gnssValid);
}

}  // namespace

StackType_t BleWorker::taskStack[BleWorker::TASK_STACK_WORDS];
StaticTask_t BleWorker::taskBuf;

BleWorker::BleWorker() = default;

BleWorker::~BleWorker() { stop(); }

bool BleWorker::start() {
    if (taskHandle) return true;
    mutex = xSemaphoreCreateMutex();
    if (!mutex) {
        NSG_LOG_ERROR("BleWorker::start", "failed to create mutex");
        return false;
    }
    stopFlag = false;
    taskHandle = xTaskCreateStaticPinnedToCore(taskEntry, "BleWorker", TASK_STACK_WORDS, this, 1, taskStack, &taskBuf, 0);
    if (!taskHandle) {
        NSG_LOG_ERROR("BleWorker::start", "failed to create task");
        vSemaphoreDelete(mutex);
        mutex = nullptr;
        return false;
    }
    return true;
}

void BleWorker::stop() {
    if (taskHandle) {
        stopFlag = true;
        // the worker checks stopFlag between passes and between cameras in
        // the broadcast loop (step 3), so once a stop is requested the
        // longest sequence left is a single in-flight BLE operation: one
        // handshake (~45-60s, measured up to 58.7s in issue #25) or one
        // blocked TIME+GEO write pair (~30s per write). Budget 90s for that
        // plus headroom; force-deleting the task mid-BLE-op would leak the
        // GATTC app registration — the very zombie-slot bug (issue #25) the
        // teardown logic exists to fix.
        for (int i = 0; i < 900 && taskHandle != nullptr; ++i) {
            vTaskDelay(pdMS_TO_TICKS(100));
        }
        if (taskHandle != nullptr) {
            NSG_LOG_WARN("BleWorker::stop", "task did not exit gracefully, force deleting");
            vTaskDelete(taskHandle);
            taskHandle = nullptr;
        }
    }
    if (scanner) {
        scanner->stopScanning();
        scanner.reset();
    }
    connectedCameras.clear();
    if (mutex) {
        vSemaphoreDelete(mutex);
        mutex = nullptr;
    }
}

void BleWorker::setGnssSnapshot(const GnssSnapshot& snap) {
    Lock lk(*this);
    gnssSnap = snap;
}

BleStatusSnapshot BleWorker::getBleStatusSnapshot() {
    Lock lk(*this);
    return bleSnap;
}

BleWorker::Lock::Lock(BleWorker& w) : w(w) {
    if (w.mutex) xSemaphoreTake(w.mutex, portMAX_DELAY);
}

BleWorker::Lock::~Lock() {
    if (w.mutex) xSemaphoreGive(w.mutex);
}

size_t BleWorker::countActiveBLEConnections() {
    size_t count = 0;
    for (const auto& item : connectedCameras) {
        if (item.pClient && item.pClient->isConnected()) {
            count++;
        }
    }
    return count;
}

bool BleWorker::isRTCValid() {
    // hold the BLE worker's lock so it cannot read the RTC mid-write
    Lock lk(*this);
    auto datetime = readSystemRTC();
    return datetime.year >= 2026;
}

void BleWorker::taskEntry(void* arg) {
    auto* self = static_cast<BleWorker*>(arg);
    self->taskLoop();
    self->taskHandle = nullptr;
    vTaskDelete(nullptr);
}

void BleWorker::taskLoop() {
    // init: load saved cameras + scanner
    auto savedCameras = Config::getSavedCameras();
    connectedCameras.reserve(savedCameras.size());
    for (const auto& saved : savedCameras) {
        NSG_LOG_INFO("BleWorker::taskLoop", "Loading saved camera %s", saved.bleName.c_str());
        connectedCameras.emplace_back(saved);
    }

    scanner.reset(new NikonBLEScanner(NikonBLEScannerMode::PAIRED));
    if (!scanner->startScanning()) {
        NSG_LOG_FATAL("BleWorker::taskLoop", "failed to start BLE scanning");
    }

    // RTC-valid edge tracker for the liveness watchdog in step 2: its
    // deadline must be re-armed when the GNSS time sync lands, because
    // silence accumulated before that moment is expected.
    bool rtcWasValid = false;

    while (!stopFlag) {
        bool scanStopped = false;
        bool handshakeAttempted = false;

        // 1. block up to 1s for a scan result. The timeout doubles as the
        //    stop-flag poll interval and keeps the 30s broadcast timer ticking
        //    even with no advertising cameras. The result is only buffered
        //    here; (re)connects are attempted in step 4, after due payloads
        //    have been served — a handshake can block this single-threaded
        //    worker for up to ~45s and must not starve connected cameras.
        ScannedCamera scanned;
        bool hasScanResult = xQueueReceive(scanner->scanResultQueue, &scanned, pdMS_TO_TICKS(1000));

        // 2. liveness watchdog: a zombified link can leave isConnected() stuck
        //    true with no disconnect event ever delivered, so the teardown in
        //    step 4 never fires and the client holds its BLE slot until
        //    reboot (issue #25). Destroy a connected client that hasn't
        //    completed anything within the deadline. Before the RTC is valid,
        //    payloads are legitimately never sent, so silence from a healthy
        //    connected camera is expected there: the deadline is tripled
        //    pre-sync (a healthy camera then merely re-handshakes when the
        //    tripled deadline cycles it — harmless, and the price for
        //    recovering zombie slots even when the GNSS never syncs, e.g.
        //    indoors) and it is re-armed on the invalid->valid edge, so a
        //    slow GNSS cold start (minutes, easily past the deadline) does
        //    not drop healthy cameras the moment the clock syncs.
        const bool rtcValid = isRTCValid();
        if (BleRetryPolicy::shouldRearmLivenessOnRtcEdge(rtcValid, rtcWasValid)) {
            const uint32_t rearmMs = millis();
            for (auto& item : connectedCameras) {
                if (item.pClient && item.pClient->isConnected()) {
                    item.lastCommOkMillis = rearmMs;
                }
            }
        }
        rtcWasValid = rtcValid;
        {
            const uint32_t deadlineMs = BleRetryPolicy::effectiveClientDeadlineMs(rtcValid, NIKON_BLE_CLIENT_DEADLINE_MS);
            const uint32_t nowMs = millis();
            for (auto& item : connectedCameras) {
                if (!item.pClient || !item.pClient->isConnected()) continue;
                const uint32_t lastCommOkMs = item.lastCommOkMillis;
                if (BleRetryPolicy::isClientStale(nowMs, lastCommOkMs, deadlineMs)) {
                    NSG_LOG_WARN("BleWorker", "No successful communication with %s for %lu ms (deadline %lu ms), dropping the client",  //
                                 item.info.bleName.c_str(), (unsigned long)(nowMs - lastCommOkMs), (unsigned long)deadlineMs);
                    item.pClient.reset();
                }
            }
        }

        // 3. periodic broadcast: gather shared state under the mutex
        GnssSnapshot snap;
        {  // scope for lock to deconstruct when exit
            Lock lk(*this);
            snap = gnssSnap;
        }

        // only send payload when RTC is valid, since GEO payload has time info
        // and the camera will reject it if the time drifts from its own clock.
        // Skipped once a stop was requested: blocked GATT writes would only
        // extend the shutdown join in stop().
        if (rtcValid && !stopFlag) {
            TimeMessage timeMessage(0, 0, 0, 0, 0, 0, 0, 0, 0);
            for (auto& item : connectedCameras) {
                // check the stop flag between cameras: without this, every
                // remaining camera could add a blocked TIME+GEO write pair
                // (~30s per write), keeping one pass — and with it the
                // shutdown join in stop() — busy for minutes and exceeding
                // its budget, forcing a task delete that leaks the GATTC app
                // registration (issue #25's zombie slot)
                if (stopFlag) break;
                if (millis() - item.lastBroadcastMillis < NIKON_BLE_UPDATE_INTERVAL_MS) continue;
                if (!item.pClient) continue;
                if (!item.pClient->isConnected()) continue;

                // stop scanning to free up the antenna
                if (!scanStopped) {
                    scanner->stopScanning();
                    scanStopped = true;
                }
                // sending TIME payload, first getting the latest time
                RtcSnapshot dt;
                {
                    Lock lk(*this);
                    dt = readSystemRTC();
                }
                updateTimeMessageWithRTC(timeMessage, dt);
                NSG_LOG_INFO("BleWorker", "Sending TIME payload to %s...", item.info.bleName.c_str());
                if (!item.pClient->sendTimePayload(timeMessage)) {
                    // the client is dead; fully destroy it so the stack
                    // releases the BLE slot. A mere disconnect() leaves the
                    // slot stuck on a zombie link (issue #25).
                    NSG_LOG_WARN("BleWorker", "Failed to send TIME payload to %s, dropping the client", item.info.bleName.c_str());
                    item.pClient.reset();
                    // the client is gone, skip the GEO payload for this cycle
                    continue;
                }
                item.lastCommOkMillis = millis();

                // sending GEO payload, skip if we already sent an invalid GEO payload
                // otherwise, if we kept sending invalid GEO payload, camera will reject
                if (item.lastGeoValid || snap.gnssValid) {
                    NSG_LOG_INFO("BleWorker", "Sending GEO payload to %s...", item.info.bleName.c_str());
                    auto geoMessage = generateGeoMessage(snap, dt);
                    if (!item.pClient->sendGeoPayload(geoMessage)) {
                        // camera rejected the message, set last geo invalid so we won't send invalid GEO again on reconnect
                        item.lastGeoValid = false;
                        NSG_LOG_WARN("BleWorker", "Failed to send GEO payload to %s, dropping the client", item.info.bleName.c_str());
                        item.pClient.reset();
                        continue;
                    }
                    item.lastGeoValid = snap.gnssValid;
                    item.lastCommOkMillis = millis();
                }
                // update broadcast time
                item.lastBroadcastMillis = millis();
            }
        }

        // 4. handle the buffered scan result, then drain the rest
        //    (non-blocking). A camera advertising means it is (or wants to
        //    be) connected: tear down its disconnected client and reconnect.
        //    Skipped once a stop was requested: a fresh handshake can block
        //    for ~45-60s and would only extend the shutdown join in stop().
        if (hasScanResult && !stopFlag) {
            do {
                for (auto& item : connectedCameras) {
                    if (item.info.bleName == scanned.name && item.info.device == scanned.device) {
                        if (item.pClient && !item.pClient->isConnected()) {
                            // disconnected, kill current client and restart
                            item.pClient->disconnect();
                            item.pClient.reset();
                        }
                        if (!item.pClient) {
                            // retry gate: a camera that keeps failing to
                            // connect is retried at most once per interval,
                            // not on every advertisement (issue #25). The
                            // gate is armed when an attempt finishes —
                            // failed, or skipped for full slots (below) — so
                            // the interval counts from the END of the failed
                            // attempt: arming it before doHandshake would let
                            // a ~45s blocking attempt eat the whole interval,
                            // making the gate (and the log message below) a
                            // no-op for slow failures.
                            if (!BleRetryPolicy::shouldAttemptReconnect(millis(), item.lastConnectAttemptMillis,
                                                                        NIKON_BLE_CONNECT_RETRY_INTERVAL_MS)) {
                                continue;
                            }
                            // at most one handshake per pass: handshakes can
                            // block for up to ~45s; other cameras retry on
                            // their next advertisement (next pass is <=1s away)
                            if (handshakeAttempted) {
                                continue;
                            }
                            if (countActiveBLEConnections() >= CONFIG_BTDM_CTRL_BLE_MAX_CONN) {
                                NSG_LOG_WARN("BleWorker", "Max BLE connections (%d) reached, skipping %s", CONFIG_BTDM_CTRL_BLE_MAX_CONN,
                                             item.info.bleName.c_str());
                                // a skipped attempt is still a failed attempt
                                // for this camera: arm the retry gate so this
                                // path (and its warning) is reconsidered at
                                // most once per retry interval instead of on
                                // every advertisement while all slots are
                                // busy. Cost: once a slot frees, the waiting
                                // camera reconnects within one retry interval
                                // instead of immediately.
                                item.lastConnectAttemptMillis = millis();
                                continue;
                            }
                            // arm the pass cap before attempting: a handshake
                            // that blocks for ~45s still counts against this
                            // pass even if it never returns to this line
                            handshakeAttempted = true;
                            item.pClient.reset(new NikonBLEClient(rnd, item.info.device, item.info.nonce));
                            if (!scanStopped) {
                                // stop scanning to free up the antenna
                                scanner->stopScanning();
                                scanStopped = true;
                            }
                            auto bleAddr = BLEAddress(scanned.addr);
                            if (!item.pClient->doHandshake(bleAddr, scanned.addrType)) {
                                NSG_LOG_ERROR("BleWorker", "Failed to reconnect to %s due to handshake failure, next attempt in %d ms",
                                              bleAddr.toString().c_str(), NIKON_BLE_CONNECT_RETRY_INTERVAL_MS);
                                // arm the retry gate now that the attempt has
                                // actually finished (see the gate comment above)
                                item.lastConnectAttemptMillis = millis();
                                // clean up stale client asap
                                item.pClient.reset();
                            } else {
                                NSG_LOG_INFO("BleWorker", "BLE connected to %s", bleAddr.toString().c_str());
                                item.lastBroadcastMillis = 0;
                                item.lastCommOkMillis = millis();
                            }
                        }
                    }
                }
                yield();
            } while (!stopFlag && xQueueReceive(scanner->scanResultQueue, &scanned, (TickType_t)0));
        }

        // 5. refresh the status snapshot for the UI.
        {
            Lock lk(*this);
            bleSnap.activeConnections = countActiveBLEConnections();
            bleSnap.pairedCount = connectedCameras.size();
        }

        // 6. resume scanning if we stopped it for radio-sensitive operations.
        if (scanStopped && !stopFlag) {
            if (!scanner->startScanning()) {
                NSG_LOG_FATAL("BleWorker", "failed to start BLE scanning");
            }
        }
    }

    // cleanup on stop
    if (scanner) {
        scanner->stopScanning();
    }
    for (auto& item : connectedCameras) {
        if (item.pClient) {
            item.pClient->disconnect();
            item.pClient.reset();
        }
    }
}
