#include "ConnectedCamera.h"

ConnectedCamera::ConnectedCamera(const SavedCameraInfo& info) : info(info), pClient(nullptr), lastBroadcastMillis(0) {}

ConnectedCamera::~ConnectedCamera() = default;
