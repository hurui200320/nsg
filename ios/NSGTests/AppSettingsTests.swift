import Foundation
import CoreBluetooth
import CoreLocation
import Testing
@testable import NSG

@MainActor
struct AppSettingsTests {
    @Test("Nearby discovery stops immediately and resumes only when enabled")
    func nearbyDiscoveryToggle() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        context.service.setDiscoveryVisible(true)
        context.transport.emit(.stateChanged(.poweredOn))
        #expect(context.service.isScanning)

        context.services.setNearbyScanningEnabled(false)
        #expect(!context.service.isScanning)
        let scans = context.transport.scans.count
        context.transport.emit(.scanningChanged(true))
        context.transport.emit(.discovered(CameraDevice(id: UUID(), name: "Nearby"), nil))
        context.service.startScan()
        context.service.setDiscoveryVisible(false)
        context.service.setDiscoveryVisible(true)
        context.service.prepare()
        #expect(!context.service.isScanning)
        #expect(context.service.devices.isEmpty)
        #expect(context.transport.scans.count == scans)

        context.services.setNearbyScanningEnabled(true)
        #expect(context.service.isScanning)
        #expect(context.transport.scans.count == scans + 1)

        let session = try context.connect()
        context.finishHandshake(session)
        context.services.setNearbyScanningEnabled(false)
        #expect(context.service.connectionState == .ready)
        #expect(context.transport.disconnections.isEmpty)
        #expect(context.location.isRunning)
    }

    @Test("Turning off nearby discovery preserves saved-camera rediscovery")
    func savedCameraRediscovery() throws {
        let target = CameraTestContext.camera(connectedAt: .now)
        let context = try CameraTestContext(cameras: [target])
        defer { context.cleanup() }
        context.service.setDiscoveryVisible(true)
        context.transport.emit(.stateChanged(.poweredOn))
        #expect(context.service.connectionState == .reconnecting)

        context.services.setNearbyScanningEnabled(false)
        #expect(context.transport.scans.last == .reconnection)
        #expect(context.service.isAutomaticReconnectEnabled)
        context.transport.emit(.discovered(CameraDevice(id: UUID(), name: "Other camera"), nil))
        #expect(context.service.devices.isEmpty)
        #expect(context.transport.connections.isEmpty)

        context.transport.emit(.discovered(CameraDevice(id: target.peripheralIdentifier, name: target.name), nil))
        #expect(context.transport.connections.last?.0.id == target.peripheralIdentifier)
        #expect(context.service.devices.isEmpty)
    }

    @Test("Automatic sends wait for the selected interval", arguments: LocationSendInterval.allCases)
    func selectedSendInterval(_ interval: LocationSendInterval) throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        context.services.setLocationSendInterval(interval)
        let session = try context.connect()
        context.finishHandshake(session)
        context.location.emit(context.fix())
        context.transport.emit(.writeCompleted(session, .location, nil))
        context.scheduler.advance(by: interval.rawValue - 1)
        context.location.emit(context.fix())
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 1)
        context.scheduler.advance(by: 1)
        context.location.emit(context.fix())
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 2)
    }

    @Test("Changing the send interval applies to the current connection")
    func changeIntervalWhileConnected() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        context.services.setLocationSendInterval(.oneMinute)
        let session = try context.connect()
        context.finishHandshake(session)
        context.location.emit(context.fix())
        context.transport.emit(.writeCompleted(session, .location, nil))
        context.scheduler.advance(by: 30)
        context.location.emit(context.fix())
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 1)
        context.services.setLocationSendInterval(.tenSeconds)
        context.location.emit(context.fix())
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 2)
    }

    @Test("Accuracy threshold applies to automatic and manual sends", arguments: LocationAccuracy.allCases)
    func selectedAccuracy(_ accuracy: LocationAccuracy) throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        context.services.setLocationAccuracy(accuracy)
        let session = try context.connect()
        context.finishHandshake(session)
        let inaccurate = fix(in: context, accuracy: accuracy.rawValue + 1)
        context.location.emit(inaccurate)
        context.service.sendCurrentLocation()
        #expect(context.transport.writes.filter { $0.0 == .location }.isEmpty)

        context.location.emit(fix(in: context, accuracy: accuracy.rawValue))
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 1)
        context.transport.emit(.writeCompleted(session, .location, nil))
        context.scheduler.advance(by: 31)
        context.service.sendCurrentLocation()
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 1)
    }

    @Test("Stricter accuracy rejects the cached fix without restarting GPS")
    func changeAccuracyWhileConnected() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        context.services.setLocationAccuracy(.hundredMeters)
        let session = try context.connect()
        context.finishHandshake(session)
        context.location.emit(fix(in: context, accuracy: 50))
        context.transport.emit(.writeCompleted(session, .location, nil))
        context.services.setLocationAccuracy(.tenMeters)
        context.service.sendCurrentLocation()
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 1)
        #expect(context.location.isRunning)
    }

    @Test("Settings survive controller recreation and configure services before startup")
    func persistedSettings() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        context.services.setNearbyScanningEnabled(false)
        context.services.setLocationSendInterval(.fiveMinutes)
        context.services.setLocationAccuracy(.fiftyMeters)

        let cameraService = NikonCameraService(
            defaults: context.defaults, transport: FakeCameraTransport(),
            scheduler: context.scheduler, locationSource: FakeLocationSource()
        )
        let restored = AppServiceController(cameraService: cameraService, defaults: context.defaults)
        #expect(!restored.isNearbyScanningEnabled)
        #expect(!cameraService.isNearbyScanningEnabled)
        #expect(restored.locationSendInterval == .fiveMinutes)
        #expect(cameraService.locationSync.sendInterval == 300)
        #expect(restored.locationAccuracy == .fiftyMeters)
        #expect(cameraService.locationService.maximumHorizontalAccuracy == 50)
        #expect(!cameraService.locationService.isRunning)
    }

    private func fix(in context: CameraTestContext, accuracy: Double) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.5, longitude: 139.75),
            altitude: 10, horizontalAccuracy: accuracy, verticalAccuracy: 8,
            timestamp: context.scheduler.now
        )
    }
}
