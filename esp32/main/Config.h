#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <vector>

class SavedCameraInfo {
public:
    SavedCameraInfo(String bleName, uint32_t device, uint32_t nonce);

    String bleName;
    uint32_t device;
    uint32_t nonce;

    void addToJsonArray(JsonDocument &parent);
};

namespace Config {
    /**
     * Get the persisted device ID, generating and saving one if it does not exist.
     */
    uint32_t getOrGenerateId();

    std::vector<SavedCameraInfo> getSavedCameras();

    void addToSavedCameras(SavedCameraInfo cameraInfo);
} // namespace Config

#endif  // CONFIG_H
