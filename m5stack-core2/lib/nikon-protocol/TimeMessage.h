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
    int8_t dst_offset;
    int8_t tz_offset_hours;
    int8_t tz_offset_minutes;

    TimeMessage(
        uint16_t year, uint8_t month, uint8_t day,
        uint8_t hour, uint8_t minute, uint8_t second,
        int8_t dst_offset, int8_t tz_offset_hours, int8_t tz_offset_minutes
    );

    /**
     * Encodes this message into the supplied 10-byte buffer.
     * The caller must ensure [buffer] has room for at least [SIZE] bytes.
     */
    void encode(uint8_t *buffer) const;

    /**
     * Decodes a TimeMessage from a 10-byte buffer.
     * The caller must ensure [data] has at least [SIZE] bytes.
     */
    static TimeMessage decode(const uint8_t *data);

    bool operator==(const TimeMessage &other) const;
};

#endif // TIME_MESSAGE_H
