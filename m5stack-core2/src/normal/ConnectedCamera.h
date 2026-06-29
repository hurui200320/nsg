#ifndef CONNECTED_CAMERA_H
#define CONNECTED_CAMERA_H

#include <memory>

#include "../common/NikonBLEClient.h"
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
    uint32_t lastBroadcastMillis;
};

#endif