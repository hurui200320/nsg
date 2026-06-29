#include "Utils.h"


std::string Utils::hexStr(const uint8_t* data, size_t len) {
    std::string result;
    result.reserve(len * 2);
    static constexpr char hex[] = "0123456789abcdef";
    for (size_t i = 0; i < len; ++i) {
        result.push_back(hex[data[i] >> 4]);
        result.push_back(hex[data[i] & 0x0F]);
    }
    return result;
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

std::string Utils::generateFullId(const uint32_t id) { 
    auto idStr = Utils::uint32ToLittleEndianHexString(id);
    return std::string("nsg-") + idStr;
 }
