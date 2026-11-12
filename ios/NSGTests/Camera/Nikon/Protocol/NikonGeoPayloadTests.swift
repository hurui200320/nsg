import Foundation
import Testing

@testable import NSG

@MainActor
struct NikonGeoPayloadTests {
    private let now = Date(timeIntervalSince1970: 1_793_703_600)

    @Test("GEO encoding matches every byte of the reference payload")
    func geoPayloadMatchesReferenceBytes() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-03T11:00:00Z"))
        let data = try NikonGeoPayload.make(
            latitude: 35.5,
            longitude: 139.75,
            altitude: 10,
            date: date
        )
        var expected: [UInt8] = [
            0x7F, 0x00,
            0x4E, 35, 30, 0, 0,
            0x45, 139, 45, 0, 0,
            8, 0x50, 10, 0,
            0xEA, 0x07, 11, 3, 11, 0, 0,
            0, 1,
            0x57, 0x47, 0x53, 0x2D, 0x38, 0x34,
        ]
        expected += [UInt8](repeating: 0, count: 10)
        #expect(data == Data(expected))
        #expect(data.count == 41)
    }

    @Test("Encode southern and western hemispheres, negative altitudes, and metric upper bounds")
    func geoPayloadEncodesNegativeCoordinatesAndAltitude() throws {
        let data = Array(
            try NikonGeoPayload.make(
                latitude: -35.5,
                longitude: -139.75,
                altitude: -65535,
                date: now
            )
        )
        #expect(data[2] == 0x53)
        #expect(data[7] == 0x57)
        #expect(data[13] == 0x4D)
        #expect(data[14] == 0xFF && data[15] == 0xFF)
    }

    @Test("Reject out-of-range and non-finite coordinates, altitudes, and times")
    func geoPayloadRejectsValuesOutsideEncodingRange() {
        #expect(throws: NikonGeoError.self) {
            _ = try NikonGeoPayload.make(latitude: .nan, longitude: 0, altitude: 0, date: now)
        }
        #expect(throws: NikonGeoError.self) {
            _ = try NikonGeoPayload.make(latitude: 0, longitude: 181, altitude: 0, date: now)
        }
        #expect(throws: NikonGeoError.self) {
            _ = try NikonGeoPayload.make(latitude: 0, longitude: 0, altitude: 65536, date: now)
        }
        #expect(throws: NikonGeoError.self) {
            _ = try NikonGeoPayload.make(
                latitude: 0,
                longitude: 0,
                altitude: 0,
                date: Date(timeIntervalSince1970: .nan)
            )
        }
    }
}
