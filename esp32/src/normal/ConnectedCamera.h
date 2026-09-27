#ifndef CONNECTED_CAMERA_H
#define CONNECTED_CAMERA_H

#include <memory>

#include "common/NikonBLEClient.h"
#include "Config.h"

class ConnectedCamera {
   public:
    explicit ConnectedCamera(const SavedCameraInfo& info);
    ~ConnectedCamera();

    // Non-copyable: the BLE client is a unique resource.
    ConnectedCamera(const ConnectedCamera&) = delete;
    ConnectedCamera& operator=(const ConnectedCamera&) = delete;

    // Movable
    ConnectedCamera(ConnectedCamera&&) = default;
    ConnectedCamera& operator=(ConnectedCamera&&) = default;

    SavedCameraInfo info;
    std::unique_ptr<NikonBLEClient> pClient;
    uint32_t lastBroadcastMillis = 0;

    bool lastGeoValid = false;

    // --- Worker-task-only bookkeeping (see lib/utils/BleRetryPolicy.h) ---
    // millis() of the last FAILED reconnect/handshake attempt for this
    // camera — including an attempt skipped entirely because all BLE slots
    // were busy — 0 = none on record. Gates how often a failing camera is
    // retried; armed when the attempt finishes (not when it starts), so a
    // slow ~45s attempt still yields a full retry interval of rest.
    uint32_t lastConnectAttemptMillis = 0;
    // millis() of the last successful handshake or TIME/GEO write,
    // 0 = none yet. Feeds the stale-client (liveness) watchdog; re-armed
    // when the RTC becomes valid, since silence before the GNSS time
    // sync is expected, not a zombie sign.
    uint32_t lastCommOkMillis = 0;
};

#endif  // CONNECTED_CAMERA_H
