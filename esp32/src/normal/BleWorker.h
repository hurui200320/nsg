#ifndef BLE_WORKER_H
#define BLE_WORKER_H

#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/task.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <vector>

#include "common/NikonBLEClient.h"
#include "common/NikonBLEScanner.h"
#include "ConnectedCamera.h"
#include "Esp32RandomGenerator.h"
#include "Snapshots.h"

// Min interval between TIME/GEO broadcasts sent to a single camera.
#ifndef NIKON_BLE_UPDATE_INTERVAL_MS
#define NIKON_BLE_UPDATE_INTERVAL_MS 30000
#endif

// Min wait between reconnect attempts for the same camera. Without this, a
// camera that keeps failing to connect (switched off, out of range, or the
// stack refusing locally because no resource is free) is retried on every
// advertisement — several hundred times per minute (see issue #25).
#ifndef NIKON_BLE_CONNECT_RETRY_INTERVAL_MS
#define NIKON_BLE_CONNECT_RETRY_INTERVAL_MS 10000
#endif

// A connected client with no successful handshake or payload write for this
// long is treated as a zombie (isConnected() stuck true after the link died
// without a disconnect event) and destroyed so its BLE slot is released.
// Until the RTC is valid the worker triples this deadline (see taskLoop):
// payloads are legitimately never sent before the GNSS time sync, so only
// handshakes refresh a healthy camera's liveness timestamp then.
//
// The deadline must survive a worst-case pass sequence for a healthy camera
// whose due-check was just missed: its own update interval, one further
// interval during which another camera's blocked TIME write can delay the
// worker (~30s write timeout — the follow-up GEO write never happens, the
// client is dropped on the first failed write, so a slow pair cannot
// chain), and one handshake (at most one runs per pass, its connect timeout
// alone is NIKON_BLE_CONNECT_TIMEOUT_MS). The assert below encodes that;
// real-world writes finish in well under a second, leaving generous headroom.
#ifndef NIKON_BLE_CLIENT_DEADLINE_MS
#define NIKON_BLE_CLIENT_DEADLINE_MS 120000
#endif

static_assert(NIKON_BLE_CLIENT_DEADLINE_MS > 2 * NIKON_BLE_UPDATE_INTERVAL_MS + NIKON_BLE_CONNECT_TIMEOUT_MS,  //
              "NIKON_BLE_CLIENT_DEADLINE_MS is too tight: a healthy camera delayed by one blocked write plus one handshake would be dropped as a zombie");

#ifndef TZ_OFFSET_HOUR
#define TZ_OFFSET_HOUR 8
#endif

// Owns all application-level BLE work and runs it on a dedicated core-0 task,
// offloading the core-1 loop so the screen keeps drawing during (re)connects.
//
// Concurrency rules:
//  - `scanner`, `connectedCameras`, `rnd` are touched ONLY by the worker task.
//  - `GnssSnapshot` / `BleStatusSnapshot` are read/written under the mutex.
//  - RTC reads the worker performs for payload building run under the same
//    mutex as the snapshots, so they cannot race with the core-1 time-sync
//    write (for example, M5.Rtc.setDateTime).
class BleWorker {
   public:
    // 16 KB stack (4096 words of StackType_t), placed in internal RAM via
    // static buffers (a dynamic stack could land in PSRAM under
    // CONFIG_SPIRAM_USE_MALLOC, which is unsafe for task stacks).
    // 16 KB is needed because the worker task frame holds all locals
    // (GnssSnapshot, TimeMessage, GeoMessage, …) simultaneously, and calls
    // Config::getSavedCameras() which puts a ~256-byte JsonDocument on the
    // stack plus deserializeJson overhead — all before the BLE handshake
    // (Blowfish + GATT) adds its own depth.
    static constexpr size_t TASK_STACK_WORDS = 4096;

    BleWorker();
    ~BleWorker();

    // Create the worker task pinned to core 0. Returns false on failure.
    bool start();

    // Signal the worker to stop and join it. Safe to call multiple times.
    void stop();

    // Feed GNSS/RTC state from the core-1 loop (thread-safe).
    void setGnssSnapshot(const GnssSnapshot& snap);

    // Read BLE status for the screen (thread-safe).
    BleStatusSnapshot getBleStatusSnapshot();

    // RAII guard for shared resources protected by the internal mutex
    // (snapshots + RTC). Usable from any task.
    class Lock {
       public:
        explicit Lock(BleWorker& w);
        ~Lock();

       private:
        BleWorker& w;
    };

   private:
    // BLE-owned resources: touched ONLY by the worker task.
    Esp32RandomGenerator rnd;
    std::unique_ptr<NikonBLEScanner> scanner;
    std::vector<ConnectedCamera> connectedCameras;

    // Cross-task state, guarded by mutex.
    SemaphoreHandle_t mutex = nullptr;
    GnssSnapshot gnssSnap;
    BleStatusSnapshot bleSnap;

    // Task control.
    std::atomic<bool> stopFlag = false;
    std::atomic<TaskHandle_t> taskHandle = nullptr;
    static StackType_t taskStack[TASK_STACK_WORDS];
    static StaticTask_t taskBuf;

    static void taskEntry(void* arg);
    void taskLoop();

    // Worker-only helper.
    size_t countActiveBLEConnections();
    bool isRTCValid();
};

#endif  // BLE_WORKER_H
