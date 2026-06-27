#include "NormalMode.h"

#include <vector>

#include "Config.h"
#include "Logging.h"

NormalMode::NormalMode() {}

std::vector<SavedCameraInfo> savedCameras;

void NormalMode::setup() {
    savedCameras = Config::getSavedCameras();

    for (auto& item : savedCameras) {
        Logging::info("NormalSetup", "Saved camera: " + item.bleName + ", device=" + std::to_string(item.device));
    }
}

void NormalMode::loop() {}
