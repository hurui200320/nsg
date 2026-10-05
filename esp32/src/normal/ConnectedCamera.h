#ifndef CONNECTED_CAMERA_H
#define CONNECTED_CAMERA_H

#include <memory>

#include "BleRetryPolicy.h"
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
    // Retry gate and liveness timestamps: the gate is armed when a
    // (re)connect attempt fails or is skipped for full BLE slots, or when a
    // failed TIME/GEO write tears the client down, and cleared on a
    // successful handshake; liveness is refreshed by every successful
    // handshake or write, and re-armed on the GNSS time-sync edge. Presence
    // is tracked with booleans, not a 0-timestamp sentinel, so a record
    // landing on the millis() wraparound instant is honored.
    BleRetryPolicy::CameraTiming timing;
};

#endif  // CONNECTED_CAMERA_H
