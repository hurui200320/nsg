import Foundation

// GEO encoding ported from the device-tested NikonProbeSupport.swift.
enum NikonGeoError: LocalizedError {
    case invalidLocation

    var errorDescription: String? {
        "Location, altitude, or time is outside the Nikon GEO encoding range"
    }
}

enum NikonGeoPayload {
    /// Encodes a quality-checked fix as a 41-byte GEO payload; altitude is in meters and date is the sample
    /// timestamp encoded in UTC.
    /// Checks encoding ranges only; callers must validate fix freshness and accuracy separately.
    static func make(latitude: Double, longitude: Double, altitude: Int, date: Date) throws -> Data {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              (-65535...65535).contains(altitude), date.timeIntervalSince1970.isFinite else {
            throw NikonGeoError.invalidLocation
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let year = parts.year, (1...65535).contains(year),
              let month = parts.month, let day = parts.day, let hour = parts.hour,
              let minute = parts.minute, let second = parts.second else {
            throw NikonGeoError.invalidLocation
        }
        var bytes: [UInt8] = [0x7F, 0x00]
        bytes += coordinate(latitude, positive: 0x4E, negative: 0x53)
        bytes += coordinate(longitude, positive: 0x45, negative: 0x57)
        bytes += [8, altitude < 0 ? 0x4D : 0x50] // Protocol compatibility value from the probe; iOS does not expose a satellite count.
        let absoluteAltitude = UInt16(abs(altitude))
        bytes += [UInt8(truncatingIfNeeded: absoluteAltitude), UInt8(absoluteAltitude >> 8)]
        bytes += [UInt8(truncatingIfNeeded: year), UInt8(truncatingIfNeeded: year >> 8),
                  UInt8(month), UInt8(day), UInt8(hour), UInt8(minute), UInt8(second)]
        bytes += [0, 1] // Zero subseconds, valid fix.
        bytes += Array("WGS-84".utf8)
        bytes += [UInt8](repeating: 0, count: 10)
        return Data(bytes)
    }

    private static func coordinate(_ value: Double, positive: UInt8, negative: UInt8) -> [UInt8] {
        // One unit is 1/10000 arcminute. Truncate at that resolution.
        let units = Int((abs(value) * 600_000).rounded(.down))
        let remainder = units % 600_000
        return [value < 0 ? negative : positive, UInt8(units / 600_000),
                UInt8(remainder / 10_000), UInt8((remainder % 10_000) / 100),
                UInt8(remainder % 100)]
    }
}
