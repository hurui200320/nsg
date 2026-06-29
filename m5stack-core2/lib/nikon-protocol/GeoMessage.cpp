#include "GeoMessage.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <tuple>

namespace {

constexpr double MIN_LAT = -90.0;
constexpr double MAX_LAT = 90.0;
constexpr double MIN_LON = -180.0;
constexpr double MAX_LON = 180.0;
constexpr int32_t MIN_ALTITUDE = -65535;
constexpr int32_t MAX_ALTITUDE = 65535;
constexpr uint8_t MAX_SATELLITES = 100;

double clampCoordinate(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

}  // namespace

GeoMessage::GeoMessage(
    char latDirection, uint8_t latDegrees, uint8_t latMinutes,
    uint8_t latSubmin1, uint8_t latSubmin2,
    char lonDirection, uint8_t lonDegrees, uint8_t lonMinutes,
    uint8_t lonSubmin1, uint8_t lonSubmin2,
    uint8_t satellites, char altitudeRef, uint16_t altitude,
    uint16_t year, uint8_t month, uint8_t day,
    uint8_t hour, uint8_t minute, uint8_t second,
    uint8_t centiseconds, uint8_t valid
) : latDirection(latDirection), latDegrees(latDegrees), latMinutes(latMinutes),
    latSubmin1(latSubmin1), latSubmin2(latSubmin2),
    lonDirection(lonDirection), lonDegrees(lonDegrees), lonMinutes(lonMinutes),
    lonSubmin1(lonSubmin1), lonSubmin2(lonSubmin2),
    satellites(satellites), altitudeRef(altitudeRef), altitude(altitude),
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
    lat = clampCoordinate(lat, MIN_LAT, MAX_LAT);
    lon = clampCoordinate(lon, MIN_LON, MAX_LON);

    if (altitude < MIN_ALTITUDE) altitude = MIN_ALTITUDE;
    if (altitude > MAX_ALTITUDE) altitude = MAX_ALTITUDE;

    if (satellites > MAX_SATELLITES) satellites = MAX_SATELLITES;

    DirectionalCoordinate latCoord = decimalToNikon(lat, 'N', 'S');
    DirectionalCoordinate lonCoord = decimalToNikon(lon, 'E', 'W');
    char altitudeRef = (altitude >= 0) ? 'P' : 'M';
    // altitude has been clamped to [-65535, 65535], so std::abs is always safe.
    uint16_t absAltitude = static_cast<uint16_t>(std::abs(altitude));

    return GeoMessage(
        latCoord.direction, latCoord.degrees, latCoord.minutes,
        latCoord.submin1, latCoord.submin2,
        lonCoord.direction, lonCoord.degrees, lonCoord.minutes,
        lonCoord.submin1, lonCoord.submin2,
        satellites, altitudeRef, absAltitude,
        year, month, day, hour, minute, second, centiseconds, valid
    );
}

bool GeoMessage::encode(uint8_t *buffer, size_t bufferSize) const {
    if (bufferSize < SIZE) {
        return false;
    }

    // Header (little-endian)
    buffer[0] = static_cast<uint8_t>(0x7F);
    buffer[1] = static_cast<uint8_t>(0x00);

    buffer[2] = static_cast<uint8_t>(latDirection);
    buffer[3] = latDegrees;
    buffer[4] = latMinutes;
    buffer[5] = latSubmin1;
    buffer[6] = latSubmin2;

    buffer[7] = static_cast<uint8_t>(lonDirection);
    buffer[8] = lonDegrees;
    buffer[9] = lonMinutes;
    buffer[10] = lonSubmin1;
    buffer[11] = lonSubmin2;

    buffer[12] = satellites;

    buffer[13] = static_cast<uint8_t>(altitudeRef);
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
    std::memcpy(&buffer[31], padding, 10);

    return true;
}

GeoMessage GeoMessage::decode(const uint8_t *data, size_t dataSize) {
    if (dataSize < SIZE) {
        return GeoMessage(
            'N', 0, 0, 0, 0,
            'E', 0, 0, 0, 0,
            0, 'P', 0,
            0, 0, 0, 0, 0, 0,
            0, 0
        );
    }


    char latDirection = static_cast<char>(data[2]);
    uint8_t latDegrees = data[3];
    uint8_t latMinutes = data[4];
    uint8_t latSubmin1 = data[5];
    uint8_t latSubmin2 = data[6];

    char lonDirection = static_cast<char>(data[7]);
    uint8_t lonDegrees = data[8];
    uint8_t lonMinutes = data[9];
    uint8_t lonSubmin1 = data[10];
    uint8_t lonSubmin2 = data[11];

    uint8_t satellites = data[12];

    char altitudeRef = static_cast<char>(data[13]);
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
        latDirection, latDegrees, latMinutes, latSubmin1, latSubmin2,
        lonDirection, lonDegrees, lonMinutes, lonSubmin1, lonSubmin2,
        satellites, altitudeRef, altitude,
        year, month, day, hour, minute, second, centiseconds, valid
    );

    std::memcpy(message.datum, &data[25], 6);
    std::memcpy(message.padding, &data[31], 10);

    return message;
}

bool GeoMessage::operator==(const GeoMessage &other) const {
    return std::tie(
               latDirection, latDegrees, latMinutes, latSubmin1, latSubmin2,
               lonDirection, lonDegrees, lonMinutes, lonSubmin1, lonSubmin2,
               satellites, altitudeRef, altitude, year, month, day,
               hour, minute, second, centiseconds, valid
           ) == std::tie(
               other.latDirection, other.latDegrees, other.latMinutes, other.latSubmin1, other.latSubmin2,
               other.lonDirection, other.lonDegrees, other.lonMinutes, other.lonSubmin1, other.lonSubmin2,
               other.satellites, other.altitudeRef, other.altitude, other.year, other.month, other.day,
               other.hour, other.minute, other.second, other.centiseconds, other.valid
           ) &&
           std::memcmp(datum, other.datum, 6) == 0 &&
           std::memcmp(padding, other.padding, 10) == 0;
}

GeoMessage::DirectionalCoordinate GeoMessage::decimalToNikon(
    double decimal, char positiveDirection, char negativeDirection
) {
    char direction = (decimal < 0.0) ? negativeDirection : positiveDirection;
    double abs = std::abs(decimal);
    uint8_t degrees = static_cast<uint8_t>(abs);
    double minutesFull = (abs - degrees) * 60.0;
    uint8_t minutes = static_cast<uint8_t>(minutesFull);
    double submin1Full = (minutesFull - minutes) * 100.0;
    uint8_t submin1 = static_cast<uint8_t>(submin1Full);
    double submin2Full = (submin1Full - submin1) * 100.0;
    uint8_t submin2 = static_cast<uint8_t>(submin2Full);

    return {direction, degrees, minutes, submin1, submin2};
}
