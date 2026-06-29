#include "ConnectedCamera.h"

ConnectedCamera::ConnectedCamera(SavedCameraInfo info) : info(info), pClient(nullptr), lastBroadcastMillis(0) {}

ConnectedCamera::~ConnectedCamera() {
    if (pClient != nullptr) {
        delete pClient;
    }
}
