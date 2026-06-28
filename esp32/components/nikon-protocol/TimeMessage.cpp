#include "TimeMessage.h"

#include <tuple>

TimeMessage::TimeMessage(
    uint16_t year, uint8_t month, uint8_t day,
    uint8_t hour, uint8_t minute, uint8_t second,
    int8_t dstOffset, int8_t tzOffsetHours, int8_t tzOffsetMinutes
) : year(year), month(month), day(day),
    hour(hour), minute(minute), second(second),
    dstOffset(dstOffset), tzOffsetHours(tzOffsetHours), tzOffsetMinutes(tzOffsetMinutes) {
}

void TimeMessage::encode(uint8_t *buffer) const {
    buffer[0] = static_cast<uint8_t>(year & 0xFF);
    buffer[1] = static_cast<uint8_t>((year >> 8) & 0xFF);
    buffer[2] = month;
    buffer[3] = day;
    buffer[4] = hour;
    buffer[5] = minute;
    buffer[6] = second;

    buffer[7] = static_cast<uint8_t>(dstOffset);
    buffer[8] = static_cast<uint8_t>(tzOffsetHours);
    buffer[9] = static_cast<uint8_t>(tzOffsetMinutes);
}

TimeMessage TimeMessage::decode(const uint8_t *data) {
    uint16_t year =
            static_cast<uint16_t>(data[0]) |
            (static_cast<uint16_t>(data[1]) << 8);

    uint8_t month = data[2];
    uint8_t day = data[3];
    uint8_t hour = data[4];
    uint8_t minute = data[5];
    uint8_t second = data[6];

    int8_t dstOffset = static_cast<int8_t>(data[7]);
    int8_t tzOffsetHours = static_cast<int8_t>(data[8]);
    int8_t tzOffsetMinutes = static_cast<int8_t>(data[9]);

    return TimeMessage(
        year, month, day,
        hour, minute, second,
        dstOffset, tzOffsetHours, tzOffsetMinutes
    );
}

bool TimeMessage::operator==(const TimeMessage &other) const {
    return std::tie(
               year, month, day, hour, minute, second,
               dstOffset, tzOffsetHours, tzOffsetMinutes
           ) == std::tie(
               other.year, other.month, other.day, other.hour, other.minute, other.second,
               other.dstOffset, other.tzOffsetHours, other.tzOffsetMinutes
           );
}
