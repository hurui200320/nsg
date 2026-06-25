#include "GeoMessage.h"

#include <cstdlib>
#include <cstring>

GeoMessage::GeoMessage(
    char lat_direction, uint8_t lat_degrees, uint8_t lat_minutes,
    uint8_t lat_submin1, uint8_t lat_submin2,
    char lon_direction, uint8_t lon_degrees, uint8_t lon_minutes,
    uint8_t lon_submin1, uint8_t lon_submin2,
    uint8_t satellites, char altitude_ref, uint16_t altitude,
    uint16_t year, uint8_t month, uint8_t day,
    uint8_t hour, uint8_t minute, uint8_t second,
    uint8_t centiseconds, uint8_t valid
) : lat_direction(lat_direction), lat_degrees(lat_degrees), lat_minutes(lat_minutes),
    lat_submin1(lat_submin1), lat_submin2(lat_submin2),
    lon_direction(lon_direction), lon_degrees(lon_degrees), lon_minutes(lon_minutes),
    lon_submin1(lon_submin1), lon_submin2(lon_submin2),
    satellites(satellites), altitude_ref(altitude_ref), altitude(altitude),
    year(year), month(month), day(day),
    hour(hour), minute(minute), second(second),
    centiseconds(centiseconds), valid(valid) {
    std::memcpy(datum, "WGS-84", 6);
    std::memset(padding, 0, 10);
}

GeoMessage GeoMessage::fromDecimal(
    double lat, double lon, int32_t altitude, uint8_t satellites,
    uint16_t year, uint8_t month, uint8_t day,
    uint8_t hour, uint8_t minute, uint8_t second,
    uint8_t centiseconds, uint8_t valid
) {
    DirectionalCoordinate lat_coord = decimalToNikon(lat, 'N', 'S');
    DirectionalCoordinate lon_coord = decimalToNikon(lon, 'E', 'W');
    char altitude_ref = (altitude >= 0) ? 'P' : 'M';
    uint16_t abs_altitude = static_cast<uint16_t>(std::abs(altitude));

    return GeoMessage(
        lat_coord.direction, lat_coord.degrees, lat_coord.minutes,
        lat_coord.submin1, lat_coord.submin2,
        lon_coord.direction, lon_coord.degrees, lon_coord.minutes,
        lon_coord.submin1, lon_coord.submin2,
        satellites, altitude_ref, abs_altitude,
        year, month, day, hour, minute, second, centiseconds, valid
    );
}

void GeoMessage::encode(uint8_t *buffer) const {
    // Header (little-endian)
    buffer[0] = static_cast<uint8_t>(0x7F);
    buffer[1] = static_cast<uint8_t>(0x00);

    buffer[2] = static_cast<uint8_t>(lat_direction);
    buffer[3] = lat_degrees;
    buffer[4] = lat_minutes;
    buffer[5] = lat_submin1;
    buffer[6] = lat_submin2;

    buffer[7] = static_cast<uint8_t>(lon_direction);
    buffer[8] = lon_degrees;
    buffer[9] = lon_minutes;
    buffer[10] = lon_submin1;
    buffer[11] = lon_submin2;

    buffer[12] = satellites;

    buffer[13] = static_cast<uint8_t>(altitude_ref);
    buffer[14] = static_cast<uint8_t>(altitude & 0xFF);
    buffer[15] = static_cast<uint8_t>((altitude >> 8) & 0xFF);

    buffer[16] = static_cast<uint8_t>(year & 0xFF);
    buffer[17] = static_cast<uint8_t>((year >> 8) & 0xFF);
    buffer[18] = month;
    buffer[19] = day;
    buffer[20] = hour;
    buffer[21] = minute;
    buffer[22] = second;
    buffer[23] = centiseconds;
    buffer[24] = valid;

    std::memcpy(&buffer[25], datum, 6);
    std::memset(&buffer[31], 0, 10);
}

GeoMessage GeoMessage::decode(const uint8_t *data) {
    char lat_direction = static_cast<char>(data[2]);
    uint8_t lat_degrees = data[3];
    uint8_t lat_minutes = data[4];
    uint8_t lat_submin1 = data[5];
    uint8_t lat_submin2 = data[6];

    char lon_direction = static_cast<char>(data[7]);
    uint8_t lon_degrees = data[8];
    uint8_t lon_minutes = data[9];
    uint8_t lon_submin1 = data[10];
    uint8_t lon_submin2 = data[11];

    uint8_t satellites = data[12];

    char altitude_ref = static_cast<char>(data[13]);
    uint16_t altitude =
        static_cast<uint16_t>(data[14]) |
        (static_cast<uint16_t>(data[15]) << 8);

    uint16_t year =
        static_cast<uint16_t>(data[16]) |
        (static_cast<uint16_t>(data[17]) << 8);
    uint8_t month = data[18];
    uint8_t day = data[19];
    uint8_t hour = data[20];
    uint8_t minute = data[21];
    uint8_t second = data[22];
    uint8_t centiseconds = data[23];
    uint8_t valid = data[24];

    GeoMessage message(
        lat_direction, lat_degrees, lat_minutes, lat_submin1, lat_submin2,
        lon_direction, lon_degrees, lon_minutes, lon_submin1, lon_submin2,
        satellites, altitude_ref, altitude,
        year, month, day, hour, minute, second, centiseconds, valid
    );

    std::memcpy(message.datum, &data[25], 6);
    std::memcpy(message.padding, &data[31], 10);

    return message;
}

bool GeoMessage::operator==(const GeoMessage &other) const {
    return lat_direction == other.lat_direction &&
           lat_degrees == other.lat_degrees &&
           lat_minutes == other.lat_minutes &&
           lat_submin1 == other.lat_submin1 &&
           lat_submin2 == other.lat_submin2 &&
           lon_direction == other.lon_direction &&
           lon_degrees == other.lon_degrees &&
           lon_minutes == other.lon_minutes &&
           lon_submin1 == other.lon_submin1 &&
           lon_submin2 == other.lon_submin2 &&
           satellites == other.satellites &&
           altitude_ref == other.altitude_ref &&
           altitude == other.altitude &&
           year == other.year &&
           month == other.month &&
           day == other.day &&
           hour == other.hour &&
           minute == other.minute &&
           second == other.second &&
           centiseconds == other.centiseconds &&
           valid == other.valid &&
           std::memcmp(datum, other.datum, 6) == 0 &&
           std::memcmp(padding, other.padding, 10) == 0;
}

GeoMessage::DirectionalCoordinate GeoMessage::decimalToNikon(
    double decimal, char positive_direction, char negative_direction
) {
    char direction = (decimal < 0.0) ? negative_direction : positive_direction;
    double abs = std::abs(decimal);
    uint8_t degrees = static_cast<uint8_t>(abs);
    double minutes_full = (abs - degrees) * 60.0;
    uint8_t minutes = static_cast<uint8_t>(minutes_full);
    double submin1_full = (minutes_full - minutes) * 100.0;
    uint8_t submin1 = static_cast<uint8_t>(submin1_full);
    double submin2_full = (submin1_full - submin1) * 100.0;
    uint8_t submin2 = static_cast<uint8_t>(submin2_full);

    return {direction, degrees, minutes, submin1, submin2};
}
