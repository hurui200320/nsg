#include "Logging.h"

#include <Arduino.h>

void Logging::debug(const std::string& logger, const std::string& msg) {
    if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_DEBUG) {
        Serial.printf("[D] %s - %s\n", logger.c_str(), msg.c_str());
    }
}

void Logging::info(const std::string& logger, const std::string& msg) {
    if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_INFO) {
        Serial.printf("[I] %s - %s\n", logger.c_str(), msg.c_str());
    }
}

void Logging::warn(const std::string& logger, const std::string& msg) {
    if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_WARN) {
        Serial.printf("[W] %s - %s\n", logger.c_str(), msg.c_str());
    }
}

void Logging::error(const std::string& logger, const std::string& msg) {
    if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_ERROR) {
        Serial.printf("[E] %s - %s\n", logger.c_str(), msg.c_str());
    }
}

[[noreturn]] void Logging::fatal(const std::string& logger, const std::string& msg) {
    while (true) {
        Logging::error(logger, msg);
        delay(1000);
    }
}
