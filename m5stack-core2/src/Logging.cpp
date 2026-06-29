#include "Logging.h"

#include <Arduino.h>

namespace {

constexpr size_t LOG_BUFFER_SIZE = 512;

void logFormatted(const char level, const char* logger, const char* fmt, va_list args) {
    char msg[LOG_BUFFER_SIZE];
    vsnprintf(msg, sizeof(msg), fmt, args);
    Serial.printf("[%lu][%c] %s - %s\n", millis(), level, logger, msg);
}

}  // namespace

void Logging::debug(const char* logger, const char* fmt, ...) {
    if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_DEBUG) {
        va_list args;
        va_start(args, fmt);
        logFormatted('D', logger, fmt, args);
        va_end(args);
    }
}

void Logging::info(const char* logger, const char* fmt, ...) {
    if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_INFO) {
        va_list args;
        va_start(args, fmt);
        logFormatted('I', logger, fmt, args);
        va_end(args);
    }
}

void Logging::warn(const char* logger, const char* fmt, ...) {
    if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_WARN) {
        va_list args;
        va_start(args, fmt);
        logFormatted('W', logger, fmt, args);
        va_end(args);
    }
}

void Logging::error(const char* logger, const char* fmt, ...) {
    if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_ERROR) {
        va_list args;
        va_start(args, fmt);
        logFormatted('E', logger, fmt, args);
        va_end(args);
    }
}

[[noreturn]] void Logging::fatal(const char* logger, const char* fmt, ...) {
    char msg[LOG_BUFFER_SIZE];
    va_list args;
    va_start(args, fmt);
    vsnprintf(msg, sizeof(msg), fmt, args);
    va_end(args);

    while (true) {
        NSG_LOG_ERROR(logger, "%s", msg);
        delay(1000);
    }
}
