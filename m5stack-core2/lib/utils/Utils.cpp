#include "Utils.h"

#include <iomanip>
#include <sstream>


std::string Utils::hexStr(const uint8_t* data, int len) {
    std::stringstream ss;
    ss << std::hex;

    for (int i(0); i < len; ++i)
        ss << std::setw(2) << std::setfill('0') << (int)data[i];

    return ss.str();
}

void Utils::uint32ToLittleEndian(const uint32_t number, uint8_t* arr) {
    arr[0] = static_cast<uint8_t>(number);
    arr[1] = static_cast<uint8_t>(number >> 8);
    arr[2] = static_cast<uint8_t>(number >> 16);
    arr[3] = static_cast<uint8_t>(number >> 24);
}

std::string Utils::uint32ToLittleEndianHexString(const uint32_t number) {
    uint8_t arr[4];
    uint32ToLittleEndian(number, arr);
    return hexStr(arr, 4);
}
