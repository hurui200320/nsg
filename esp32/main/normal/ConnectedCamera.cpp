#include "ConnectedCamera.h"

ConnectedCamera::ConnectedCamera(SavedCameraInfo info) : info(info), pClient(nullptr), lastBroadcastMillis(0) {}
