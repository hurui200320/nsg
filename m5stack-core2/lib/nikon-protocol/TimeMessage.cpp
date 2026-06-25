#include "TimeMessage.h"

TimeMessage::TimeMessage(
    uint16_t year, uint8_t month, uint8_t day,
    uint8_t hour, uint8_t minute, uint8_t second,
    int8_t dst_offset, int8_t tz_offset_hours, int8_t tz_offset_minutes
) : year(year), month(month), day(day),
    hour(hour), minute(minute), second(second),
    dst_offset(dst_offset), tz_offset_hours(tz_offset_hours), tz_offset_minutes(tz_offset_minutes) {
}

void TimeMessage::encode(uint8_t *buffer) const {
    buffer[0] = static_cast<uint8_t>(year & 0xFF);
    buffer[1] = static_cast<uint8_t>((year >> 8) & 0xFF);
    buffer[2] = month;
    buffer[3] = day;
    buffer[4] = hour;
    buffer[5] = minute;
    buffer[6] = second;

    buffer[7] = dst_offset;
    buffer[8] = static_cast<uint8_t>(tz_offset_hours);
    buffer[9] = static_cast<uint8_t>(tz_offset_minutes);
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

    uint8_t dst_offset = data[7];
    int8_t tz_offset_hours = static_cast<int8_t>(data[8]);
    int8_t tz_offset_minutes = static_cast<int8_t>(data[9]);

    return TimeMessage(
        year, month, day,
        hour, minute, second,
        dst_offset, tz_offset_hours, tz_offset_minutes
    );
}

bool TimeMessage::operator==(const TimeMessage &other) const {
    return year == other.year &&
           month == other.month &&
           day == other.day &&
           hour == other.hour &&
           minute == other.minute &&
           second == other.second &&
           dst_offset == other.dst_offset &&
           tz_offset_hours == other.tz_offset_hours &&
           tz_offset_minutes == other.tz_offset_minutes;
}
