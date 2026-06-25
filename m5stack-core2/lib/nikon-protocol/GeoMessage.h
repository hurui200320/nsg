/**
 * C++ port of GeoPayloadGenerator from kotlin-poc.
 *
 * A 41-byte GEO message used by the Nikon smart-device after handshake.
 *
 * Layout (little-endian on the wire):
 *   bytes 0-1   header 0x007F (uint16)
 *   byte 2      latitude direction, 'N' or 'S'
 *   byte 3      latitude degrees 0-90
 *   byte 4      latitude minutes 0-59
 *   byte 5      latitude sub-minutes 1, hundredths of a minute, 0-99
 *   byte 6      latitude sub-minutes 2, hundredths of the remainder, 0-99
 *   byte 7      longitude direction, 'E' or 'W'
 *   byte 8      longitude degrees 0-180
 *   byte 9      longitude minutes 0-59
 *   byte 10     longitude sub-minutes 1, hundredths of a minute, 0-99
 *   byte 11     longitude sub-minutes 2, hundredths of the remainder, 0-99
 *   byte 12     satellites count for fix (uint8)
 *   byte 13     altitude reference, 'P' (0 and positive) or 'M' (negative)
 *   bytes 14-15 altitude absolute value in meters (uint16)
 *   bytes 16-17 year (uint16)
 *   byte 18     month 1-12, UTC
 *   byte 19     day 1-31, UTC
 *   byte 20     hour 0-23, UTC
 *   byte 21     minute 0-59, UTC
 *   byte 22     second 0-59, UTC
 *   byte 23     centiseconds 0–99
 *   byte 24     valid, 1 means camera will take this, 0 means wipe old data
 *   bytes 25-30 standard, fixed to "WGS-84" (6 bytes ASCII)
 *   bytes 31-40 padding (10 bytes)
 */

#ifndef GEO_MESSAGE_H
#define GEO_MESSAGE_H

#include <cstddef>
#include <cstdint>

class GeoMessage {
public:
    static constexpr size_t SIZE = 41;

    char lat_direction;
    uint8_t lat_degrees;
    uint8_t lat_minutes;
    uint8_t lat_submin1;
    uint8_t lat_submin2;
    char lon_direction;
    uint8_t lon_degrees;
    uint8_t lon_minutes;
    uint8_t lon_submin1;
    uint8_t lon_submin2;
    uint8_t satellites;
    char altitude_ref;
    uint16_t altitude;
    uint16_t year;
    uint8_t month;
    uint8_t day;
    uint8_t hour;
    uint8_t minute;
    uint8_t second;
    uint8_t centiseconds;
    uint8_t valid;
    char datum[6];
    uint8_t padding[10];

    /**
     * Constructs a GeoMessage from raw wire-format fields.
     * The caller is responsible for ensuring values fit the protocol layout.
     */
    GeoMessage(
        char lat_direction, uint8_t lat_degrees, uint8_t lat_minutes,
        uint8_t lat_submin1, uint8_t lat_submin2,
        char lon_direction, uint8_t lon_degrees, uint8_t lon_minutes,
        uint8_t lon_submin1, uint8_t lon_submin2,
        uint8_t satellites, char altitude_ref, uint16_t altitude,
        uint16_t year, uint8_t month, uint8_t day,
        uint8_t hour, uint8_t minute, uint8_t second,
        uint8_t centiseconds, uint8_t valid
    );

    /**
     * Constructs a GeoMessage from decimal coordinates and time fields.
     *
     * [lat] ranges from -90 to 90, positive means N, negative means S.
     * [lon] ranges from -180 to 180, positive means E, negative means W.
     * [altitude] ranges from -65535 to 65535.
     * [satellites] ranges from 0 to 100.
     */
    static GeoMessage fromDecimal(
        double lat, double lon, int32_t altitude, uint8_t satellites,
        uint16_t year, uint8_t month, uint8_t day,
        uint8_t hour, uint8_t minute, uint8_t second,
        uint8_t centiseconds, uint8_t valid
    );

    /**
     * Encodes this message into the supplied 41-byte buffer.
     * The caller must ensure [buffer] has room for at least [SIZE] bytes.
     */
    void encode(uint8_t *buffer) const;

    /**
     * Decodes a GeoMessage from a 41-byte buffer.
     * The caller must ensure [data] has at least [SIZE] bytes.
     */
    static GeoMessage decode(const uint8_t *data);

    bool operator==(const GeoMessage &other) const;

private:
    struct DirectionalCoordinate {
        char direction;
        uint8_t degrees;
        uint8_t minutes;
        uint8_t submin1;
        uint8_t submin2;
    };

    static DirectionalCoordinate decimalToNikon(
        double decimal, char positive_direction, char negative_direction
    );
};

#endif // GEO_MESSAGE_H
