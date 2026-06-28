#include "Logging.h"

#include <Arduino.h>

void Logging::debug(const std::string& logger, const std::string& msg) {
    if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_DEBUG) {
        Serial.printf("[%lu][D] %s - %s\n", millis(), logger.c_str(), msg.c_str());
    }
}

void Logging::info(const std::string& logger, const std::string& msg) {
    if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_INFO) {
        Serial.printf("[%lu][I] %s - %s\n", millis(), logger.c_str(), msg.c_str());
    }
}

void Logging::warn(const std::string& logger, const std::string& msg) {
    if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_WARN) {
        Serial.printf("[%lu][W] %s - %s\n", millis(), logger.c_str(), msg.c_str());
    }
}

void Logging::error(const std::string& logger, const std::string& msg) {
    if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_ERROR) {
        Serial.printf("[%lu][E] %s - %s\n", millis(), logger.c_str(), msg.c_str());
    }
}

[[noreturn]] void Logging::fatal(const std::string& logger, const std::string& msg) {
    while (true) {
        Logging::error(logger, msg);
        delay(1000);
    }
}
