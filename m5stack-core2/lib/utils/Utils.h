#ifndef UTILS_H
#define UTILS_H

#include <stdint.h>
#include <string>

namespace Utils {

/**
 * Convert uint8 array into hex string.
 */
std::string hexStr(const uint8_t* data, int len);

/**
 * Convert a given uint32 number into 4 bytes little endian.
 */
void uint32ToLittleEndian(const uint32_t number, uint8_t* arr);

/**
 * Convert a given uint32 number into a 4-byte little-endian hex string.
 */
std::string uint32ToLittleEndianHexString(const uint32_t number);
    
}  // namespace Utils

#endif  // UTILS_H
