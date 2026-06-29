#ifndef CONNECTED_CAMERA_H
#define CONNECTED_CAMERA_H

#include "../common/NikonBLEClient.h"
#include "Config.h"

class ConnectedCamera {
   public:
    ConnectedCamera(SavedCameraInfo info);
    ~ConnectedCamera();
    SavedCameraInfo info;
    NikonBLEClient* pClient;
    uint32_t lastBroadcastMillis;
};

#endif