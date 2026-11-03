import Foundation
import CoreLocation
import Testing
@testable import NSG

@MainActor
struct NikonLocationTests {
    private let now = Date(timeIntervalSince1970: 1_793_703_600)

    private func location(
        latitude: Double = 35.5,
        longitude: Double = 139.75,
        altitude: Double = 10,
        horizontalAccuracy: Double = 5,
        verticalAccuracy: Double = 8,
        age: TimeInterval = 0
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            timestamp: now.addingTimeInterval(-age)
        )
    }

    @Test("GEO encoding matches every byte of the reference payload")
    func referencePayload() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-03T11:00:00Z"))
        let data = try NikonGeoPayload.make(
            latitude: 35.5, longitude: 139.75, altitude: 10, date: date
        )
        var expected: [UInt8] = [
            0x7F, 0x00,
            0x4E, 35, 30, 0, 0,
            0x45, 139, 45, 0, 0,
            8, 0x50, 10, 0,
            0xEA, 0x07, 11, 3, 11, 0, 0,
            0, 1,
            0x57, 0x47, 0x53, 0x2D, 0x38, 0x34
        ]
        expected += [UInt8](repeating: 0, count: 10)
        #expect(data == Data(expected))
        #expect(data.count == 41)
    }

    @Test("Encode southern and western hemispheres, negative altitudes, and metric upper bounds")
    func signedCoordinatesAndAltitude() throws {
        let data = Array(try NikonGeoPayload.make(
            latitude: -35.5, longitude: -139.75, altitude: -65535, date: now
        ))
        #expect(data[2] == 0x53)
        #expect(data[7] == 0x57)
        #expect(data[13] == 0x4D)
        #expect(data[14] == 0xFF && data[15] == 0xFF)
    }

    @Test("Reject out-of-range and non-finite coordinates, altitudes, and times")
    func invalidPayload() {
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
                latitude: 0, longitude: 0, altitude: 0, date: Date(timeIntervalSince1970: .nan)
            )
        }
    }

    @Test("Accept only fresh locations with valid horizontal accuracy and altitude")
    func locationQuality() {
        #expect(LocationQuality.isUsable(location(), now: now))
        #expect(LocationQuality.isUsable(location(horizontalAccuracy: 20, age: 30), now: now))
        #expect(!LocationQuality.isUsable(location(age: 31), now: now))
        #expect(!LocationQuality.isUsable(location(age: -6), now: now))
        #expect(!LocationQuality.isUsable(location(horizontalAccuracy: -1), now: now))
        #expect(!LocationQuality.isUsable(location(horizontalAccuracy: 21), now: now))
        #expect(!LocationQuality.isUsable(location(verticalAccuracy: -1), now: now))
        #expect(!LocationQuality.isUsable(location(altitude: 65536), now: now))
        #expect(!LocationQuality.isUsable(location(latitude: 91), now: now))
    }

    @Test("Do not start location updates or submit GPS before the connection handshake completes")
    func noLocationBeforeReady() {
        let service = BluetoothService()
        service.startLocationSync()
        #expect(!service.locationService.isRunning)
        #expect(!service.sendLocation(location(), now: now))
        #expect(service.pendingWrite == nil)
        #expect(service.locationTransferState == .idle)
    }

    @Test("Connection cleanup cancels the location write timer and clears the pending sample")
    func cleanupLocationTransfer() {
        let service = BluetoothService()
        let task = Task<Void, Never> {}
        service.geoWriteTask = task
        service.geoWriteID = UUID()
        service.pendingGeoLocation = location()
        service.pendingWrite = .geo
        service.locationTransferState = .sending
        service.clearHandshake()
        #expect(task.isCancelled)
        #expect(service.geoWriteTask == nil)
        #expect(service.geoWriteID == nil)
        #expect(service.pendingGeoLocation == nil)
        #expect(service.pendingWrite == nil)
        #expect(!service.locationService.isRunning)
        #expect(service.locationTransferState == .idle)
    }
}
