#include "Config.h"

#include <ArduinoJson.h>
#include <Preferences.h>

#include "Logging.h"
#include "RandomGenerator.h"

SavedCameraInfo::SavedCameraInfo(String bleName, uint32_t device, uint32_t nonce) : bleName(bleName), device(device), nonce(nonce) {}

void SavedCameraInfo::addToJsonArray(JsonDocument& parent) const {
    auto doc = parent.add<JsonObject>();
    doc["bleName"] = bleName;
    doc["device"] = device;
    doc["nonce"] = nonce;
}

uint32_t Config::getOrGenerateId(RandomGenerator& randomGenerator) {
    Preferences nvs;
    if (!nvs.begin("nsg", false)) {
        NSG_LOG_FATAL("Config::getOrGenerateId", "Failed to open NVS");
    }

    auto result = nvs.getUInt("id", 0);
    while (result == 0) {
        result = randomGenerator.nextUInt32();
        // really bad luck, keep trying
        if (result == 0) continue;
        // save this non-zero id
        if (!nvs.putUInt("id", result)) {
            NSG_LOG_FATAL("Config::getOrGenerateId", "Failed to save id to NVS");
        }
    }

    nvs.end();
    return result;
}

std::vector<SavedCameraInfo> Config::getSavedCameras() {
    Preferences nvs;
    // read-only; if the namespace doesn't exist yet (first boot / NVS erased),
    // there are simply no saved cameras — return empty list instead of crashing
    if (!nvs.begin("nsg", true)) {
        return {};
    }

    auto json = nvs.getString("savedCameras", "[]");
    nvs.end();

    JsonDocument doc;
    auto error = deserializeJson(doc, json);
    if (error) {
        NSG_LOG_FATAL("Config::getSavedCameras", "Failed to parse Json, error: %s", error.c_str());
    }

    std::vector<SavedCameraInfo> result;
    auto jsonArr = doc.as<JsonArray>();
    // extra for potential new item
    result.reserve(jsonArr.size() + 1);

    for (JsonObject item : jsonArr) {
        String bleName = item["bleName"];
        uint32_t device = item["device"];
        uint32_t nonce = item["nonce"];
        SavedCameraInfo obj(bleName, device, nonce);
        result.push_back(obj);
    }

    return result;
}

void Config::addToSavedCameras(const SavedCameraInfo& cameraInfo) {
    std::vector<SavedCameraInfo> cameras = getSavedCameras();

    // loop through existing cameras list and find item with the same name
    // if so, replace the existing item
    bool found = false;
    for (auto& camera : cameras) {
        if (camera.bleName == cameraInfo.bleName) {
            camera = cameraInfo;
            found = true;
            break;
        }
    }
    // otherwise push back
    if (!found) {
        cameras.push_back(cameraInfo);
    }

    JsonDocument doc;
    // convert to json array
    doc.to<JsonArray>();
    // collect items
    for (auto& camera : cameras) {
        camera.addToJsonArray(doc);
    }

    String json;
    serializeJson(doc, json);

    Preferences nvs;
    if (!nvs.begin("nsg", false)) {
        NSG_LOG_FATAL("Config::addToSavedCameras", "Failed to open NVS");
    }
    nvs.putString("savedCameras", json.c_str());
    nvs.end();
}
