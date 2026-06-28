#ifndef LOGGING_H
#define LOGGING_H

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

void debug(const std::string& logger, const std::string& msg);
void info(const std::string& logger, const std::string& msg);
void warn(const std::string& logger, const std::string& msg);
void error(const std::string& logger, const std::string& msg);

/**
 * Special helper, loop forever and print error message every second.
 */
[[noreturn]] void fatal(const std::string& logger, const std::string& msg);

}  // namespace Logging

#endif  // LOGGING_H
