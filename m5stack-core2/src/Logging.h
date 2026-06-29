#ifndef LOGGING_H
#define LOGGING_H

#include <HardwareSerial.h>

#include <cstdarg>

/**
 * Must initiate Serial before use.
 */
namespace Logging {

#define NSG_LOG_LEVEL_DEBUG 0
#define NSG_LOG_LEVEL_INFO 1
#define NSG_LOG_LEVEL_WARN 2
#define NSG_LOG_LEVEL_ERROR 3
#define NSG_LOG_LEVEL_NONE 99

#ifndef NSG_LOG_LEVEL
#define NSG_LOG_LEVEL 1
#endif

void debug(const char* logger, const char* fmt, ...);
void info(const char* logger, const char* fmt, ...);
void warn(const char* logger, const char* fmt, ...);
void error(const char* logger, const char* fmt, ...);

/**
 * Special helper, loop forever and print error message every second.
 */
[[noreturn]] void fatal(const char* logger, const char* fmt, ...);

}  // namespace Logging

#define NSG_LOG_DEBUG(logger, ...) do { if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_DEBUG) Logging::debug(logger, ##__VA_ARGS__); } while (0)
#define NSG_LOG_INFO(logger, ...)  do { if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_INFO)  Logging::info(logger, ##__VA_ARGS__); } while (0)
#define NSG_LOG_WARN(logger, ...)  do { if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_WARN)  Logging::warn(logger, ##__VA_ARGS__); } while (0)
#define NSG_LOG_ERROR(logger, ...) do { if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_ERROR) Logging::error(logger, ##__VA_ARGS__); } while (0)
#define NSG_LOG_FATAL(logger, ...) do { Logging::fatal(logger, ##__VA_ARGS__); } while (0)

#endif  // LOGGING_H
