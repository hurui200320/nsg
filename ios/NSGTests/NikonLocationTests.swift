import Foundation
import CoreLocation
import CoreBluetooth
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

    @Test("App GPS acquires before connection but cannot submit until the camera is ready")
    func noLocationBeforeReady() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        #expect(context.services.isLocationEnabled)
        #expect(context.location.isRunning)
        context.location.emit(context.fix())
        #expect(!context.service.locationSync.send(context.fix()))
        #expect(context.transport.writes.isEmpty)
    }

    @Test("Automatic sends are throttled; manual sends bypass only the interval")
    func sendThrottle() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        let session = try context.connect()
        context.finishHandshake(session)
        #expect(context.location.isRunning)
        context.location.emit(context.fix())
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 1)
        context.transport.emit(.writeCompleted(session, .location, nil))
        context.scheduler.advance(by: 9)
        context.location.emit(context.fix())
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 1)
        context.service.sendCurrentLocation()
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 2)
        context.transport.emit(.writeCompleted(session, .location, nil))
        context.scheduler.advance(by: 10)
        context.location.emit(context.fix())
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 3)
    }

    @Test("Stopping and restarting GPS preserves an in-flight write until acknowledgement")
    func stopDuringWrite() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        let session = try context.connect()
        context.finishHandshake(session)
        context.services.setLocationEnabled(true)
        context.location.emit(context.fix())
        context.services.setLocationEnabled(false)
        context.services.setLocationEnabled(true)
        context.location.emit(context.fix())
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 1)
        context.transport.emit(.writeCompleted(session, .location, nil))
        #expect(context.service.locationTransferState == .sent)
        context.scheduler.advance(by: 15)
        #expect(context.transport.disconnections.isEmpty)
    }

    @Test("ATT 0x80 retains its error and disconnects for a new handshake")
    func rejectedGeoRecovery() throws {
        let target = CameraTestContext.camera(connectedAt: Date())
        let context = try CameraTestContext(cameras: [target])
        defer { context.cleanup() }
        context.transport.emit(.stateChanged(.poweredOn))
        let device = CameraDevice(id: target.peripheralIdentifier, name: target.name)
        context.transport.emit(.discovered(device, nil))
        let session = try #require(context.transport.connections.last?.1)
        context.transport.emit(.discovering(session))
        context.transport.emit(.connected(session, CameraCapabilities(properties: [
            .pairing: [.write, .indicate], .success: [.notify], .controllerName: [.write], .location: [.write]
        ], maximumWriteLength: 512)))
        context.transport.emit(.subscriptionChanged(session, .pairing, true, nil))
        context.transport.emit(.subscriptionChanged(session, .success, true, nil))
        context.finishHandshake(session)
        context.services.setLocationEnabled(true)
        context.location.emit(context.fix())
        let error = CameraFailure(error: NSError(domain: CBATTErrorDomain, code: 0x80))
        context.transport.emit(.writeCompleted(session, .location, error))
        #expect(context.transport.disconnections == [session])
        #expect(context.location.isRunning)
        context.transport.emit(.disconnected(session, nil))
        #expect(context.service.connectionState == .waitingToReconnect)
        #expect(context.service.lastFailure?.domain == CBATTErrorDomain)
        #expect(context.service.lastFailure?.code == 0x80)
        context.scheduler.advance(by: 5)
        #expect(context.transport.scans.count == 2)
    }

    @Test("GEO timeout closes the connection; stale acknowledgements are ignored")
    func timedOutWrite() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        let session = try context.connect()
        context.finishHandshake(session)
        context.services.setLocationEnabled(true)
        context.location.emit(context.fix())
        context.scheduler.advance(by: 15)
        #expect(context.transport.disconnections == [session])
        guard case .failed = context.service.locationTransferState else {
            Issue.record("Expected GPS timeout"); return
        }
        context.transport.emit(.disconnected(session, nil))
        context.transport.emit(.writeCompleted(session, .location, nil))
        #expect(context.service.lastLocationSentAt == nil)
        #expect(context.location.isRunning)
    }
}
