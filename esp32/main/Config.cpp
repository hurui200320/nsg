#include "Config.h"

#include <ArduinoJson.h>
#include <Preferences.h>

#include "Esp32RandomGenerator.h"
#include "Logging.h"

SavedCameraInfo::SavedCameraInfo(String bleName, uint32_t device, uint32_t nonce) : bleName(bleName), device(device), nonce(nonce) {}

void SavedCameraInfo::addToJsonArray(JsonDocument& parent) {
    auto doc = parent.add<JsonObject>();
    doc["bleName"] = bleName;
    doc["device"] = device;
    doc["nonce"] = nonce;
}

uint32_t Config::getOrGenerateId() {
    Preferences nvs;
    if (!nvs.begin("nsg", false)) {
        Logging::fatal("Config::getOrGenerateId", "Failed to open NVS");
    }

    auto result = nvs.getUInt("id", 0);
    while (result == 0) {
        Esp32RandomGenerator generator;
        result = generator.nextUInt32();
        nvs.putUInt("id", result);
    }

    nvs.end();
    return result;
}

std::vector<SavedCameraInfo> Config::getSavedCameras() {
    Preferences nvs;
    // read-only
    if (!nvs.begin("nsg", true)) {
        Logging::fatal("Config::getSavedCameras", "Failed to open NVS");
    }

    auto json = nvs.getString("savedCameras", "[]");
    nvs.end();

    JsonDocument doc;
    auto error = deserializeJson(doc, json);
    if (error) {
        Logging::fatal("Config::getSavedCameras", String("Failed to parse Json, error: ") + error.c_str());
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

void Config::addToSavedCameras(SavedCameraInfo cameraInfo) {
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
        Logging::fatal("Config::addToSavedCameras", "Failed to open NVS");
    }
    nvs.putString("savedCameras", json.c_str());
    nvs.end();
}
