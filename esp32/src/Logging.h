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

// The printf format attribute makes the compiler type-check every NSG_LOG_*
// call site against its format string (arg 1 is the logger, arg 2 the
// format), promoted to a build error via -Werror=format in platformio.ini.
void debug(const char* logger, const char* fmt, ...) __attribute__((format(printf, 2, 3)));
void info(const char* logger, const char* fmt, ...) __attribute__((format(printf, 2, 3)));
void warn(const char* logger, const char* fmt, ...) __attribute__((format(printf, 2, 3)));
void error(const char* logger, const char* fmt, ...) __attribute__((format(printf, 2, 3)));

/**
 * Special helper, loop forever and print error message every second.
 */
[[noreturn]] void fatal(const char* logger, const char* fmt, ...) __attribute__((format(printf, 2, 3)));

}  // namespace Logging

#define NSG_LOG_DEBUG(logger, ...) do { if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_DEBUG) Logging::debug(logger, ##__VA_ARGS__); } while (0)
#define NSG_LOG_INFO(logger, ...)  do { if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_INFO)  Logging::info(logger, ##__VA_ARGS__); } while (0)
#define NSG_LOG_WARN(logger, ...)  do { if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_WARN)  Logging::warn(logger, ##__VA_ARGS__); } while (0)
#define NSG_LOG_ERROR(logger, ...) do { if (NSG_LOG_LEVEL <= NSG_LOG_LEVEL_ERROR) Logging::error(logger, ##__VA_ARGS__); } while (0)
#define NSG_LOG_FATAL(logger, ...) do { Logging::fatal(logger, ##__VA_ARGS__); } while (0)

#endif  // LOGGING_H
