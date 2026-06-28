#ifndef LOGGING_H
#define LOGGING_H

#include <Arduino.h>
#include <HardwareSerial.h>

#include <string>

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

void debug(const String& logger, const String& msg);
void info(const String& logger, const String& msg);
void warn(const String& logger, const String& msg);
void error(const String& logger, const String& msg);

/**
 * Special helper, loop forever and print error message every second.
 */
[[noreturn]] void fatal(const String& logger, const String& msg);

}  // namespace Logging

#endif  // LOGGING_H
