/**
* C++ port of TimeMessage from kotlin-poc.
 *
 * A 10-byte time message used by the Nikon smart-device after handshake.
 *
 * Layout (little-endian on the wire):
 *   byte 0-1 year (uint16)
 *   bytes 2  month 1-12 (uint8)
 *   bytes 3  day 1-31 (uint8)
 *   bytes 4  hour 0-23 (uint8)
 *   bytes 5  minute 0-59 (uint8)
 *   bytes 6  second 0-59 (uint8)
 *   bytes 7  daylight saving offset, unknown, recommended 0 (uint8)
 *   bytes 8  timezone-offset hours, unconfirmed, 8 means UTC+8 (int8)
 *   bytes 9  timezone-offset minutes, unconfirmed (int8)
 *
 * Note: time value should be UTC time, tz info provided via tz offsets.
 */

#ifndef TIME_MESSAGE_H
#define TIME_MESSAGE_H

#include <cstddef>
#include <cstdint>

class TimeMessage {
public:
    static constexpr size_t SIZE = 10;

    uint16_t year;
    uint8_t month;
    uint8_t day;
    uint8_t hour;
    uint8_t minute;
    uint8_t second;
    int8_t dstOffset;
    int8_t tzOffsetHours;
    int8_t tzOffsetMinutes;

    TimeMessage(
        uint16_t year, uint8_t month, uint8_t day,
        uint8_t hour, uint8_t minute, uint8_t second,
        int8_t dstOffset, int8_t tzOffsetHours, int8_t tzOffsetMinutes
    );

    /**
     * Encodes this message into the supplied buffer.
     * Returns true on success, false if [bufferSize] is too small.
     */
    bool encode(uint8_t *buffer, size_t bufferSize) const;

    /**
     * Decodes a TimeMessage from the supplied buffer.
     * Returns a default (zeroed) message if [dataSize] is too small.
     */
    static TimeMessage decode(const uint8_t *data, size_t dataSize);

    bool operator==(const TimeMessage &other) const;
};

#endif // TIME_MESSAGE_H
