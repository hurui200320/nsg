import CoreBluetooth
import Foundation
import Testing

@testable import NSG

@MainActor
struct AppSettingsTests {
    @Test("Nearby discovery stops immediately and resumes only when enabled")
    func nearbyScanningToggleStopsAndResumesDiscovery() throws {
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
        context.service.setDiscoveryVisible(false)
        context.service.setDiscoveryVisible(true)
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
    func disablingNearbyScanningPreservesTargetRediscovery() throws {
        let target = CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 200))
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
        #expect(context.transport.connections.last?.device.id == target.peripheralIdentifier)
        #expect(context.service.devices.isEmpty)
    }

    @Test("Automatic sends wait for the selected interval", arguments: LocationSendInterval.allCases)
    func automaticSendsUseSelectedInterval(_ interval: LocationSendInterval) throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        context.services.setLocationSendInterval(interval)
        let session = try context.connect()
        context.finishHandshake(session)
        context.location.emit(context.fix())
        context.transport.emit(.writeCompleted(session, .location, nil))
        context.scheduler.advance(by: interval.rawValue - 1)
        context.location.emit(context.fix())
        #expect(context.transport.writes(to: .location).count == 1)
        context.scheduler.advance(by: 1)
        context.location.emit(context.fix())
        #expect(context.transport.writes(to: .location).count == 2)
    }

    @Test("Changing the send interval applies to the current connection")
    func changingIntervalAppliesToCurrentConnection() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        context.services.setLocationSendInterval(.oneMinute)
        let session = try context.connect()
        context.finishHandshake(session)
        context.location.emit(context.fix())
        context.transport.emit(.writeCompleted(session, .location, nil))
        context.scheduler.advance(by: 30)
        context.location.emit(context.fix())
        #expect(context.transport.writes(to: .location).count == 1)
        context.services.setLocationSendInterval(.tenSeconds)
        context.location.emit(context.fix())
        #expect(context.transport.writes(to: .location).count == 2)
    }

    @Test(
        "Selected accuracy rejects imprecise fixes and manual sending rechecks freshness",
        arguments: LocationAccuracy.allCases
    )
    func sendsRejectFixesOutsideSelectedAccuracy(_ accuracy: LocationAccuracy) throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        context.services.setLocationAccuracy(accuracy)
        let session = try context.connect()
        context.finishHandshake(session)
        let inaccurate = context.fix(horizontalAccuracy: accuracy.rawValue + 1)
        context.location.emit(inaccurate)
        context.service.sendCurrentLocation()
        #expect(context.transport.writes(to: .location).isEmpty)

        context.location.emit(context.fix(horizontalAccuracy: accuracy.rawValue))
        #expect(context.transport.writes(to: .location).count == 1)
        context.transport.emit(.writeCompleted(session, .location, nil))
        context.scheduler.advance(by: 31)
        context.service.sendCurrentLocation()
        #expect(context.transport.writes(to: .location).count == 1)
    }

    @Test("Stricter accuracy rejects the cached fix without restarting GPS")
    func stricterAccuracyRejectsCachedFixWithoutRestartingGPS() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        context.services.setLocationAccuracy(.hundredMeters)
        let session = try context.connect()
        context.finishHandshake(session)
        context.location.emit(context.fix(horizontalAccuracy: 50))
        context.transport.emit(.writeCompleted(session, .location, nil))
        context.services.setLocationAccuracy(.tenMeters)
        context.service.sendCurrentLocation()
        #expect(context.transport.writes(to: .location).count == 1)
        #expect(context.location.isRunning)
    }

    @Test("Settings survive controller recreation and configure services before startup")
    func recreatedControllerAppliesSavedSettingsBeforeStartup() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        context.services.setNearbyScanningEnabled(false)
        context.services.setMapPreviewEnabled(false)
        #expect(!context.services.isMapPreviewEnabled)
        context.services.setLocationSendInterval(.fiveMinutes)
        context.services.setLocationAccuracy(.fiftyMeters)

        let cameraService = NikonCameraService(
            defaults: context.defaults,
            transport: FakeCameraTransport(),
            scheduler: context.scheduler,
            locationSource: FakeLocationSource()
        )
        let restored = AppServiceController(cameraService: cameraService, defaults: context.defaults)
        #expect(!restored.isMapPreviewEnabled)
        #expect(!restored.isNearbyScanningEnabled)
        #expect(!cameraService.isNearbyScanningEnabled)
        #expect(restored.locationSendInterval == .fiveMinutes)
        #expect(cameraService.locationSync.sendInterval == 300)
        #expect(restored.locationAccuracy == .fiftyMeters)
        #expect(cameraService.locationService.maximumHorizontalAccuracy == 50)
        #expect(!cameraService.locationService.isRunning)
    }

    @Test("Fresh settings enable discovery and map preview with ten-second, twenty-meter location policy")
    func freshSettingsUseAppDefaults() throws {
        let context = try CameraTestContext(startsLocation: false)
        defer { context.cleanup() }

        #expect(context.services.isNearbyScanningEnabled)
        #expect(context.services.isMapPreviewEnabled)
        #expect(context.services.locationSendInterval == .tenSeconds)
        #expect(context.services.locationAccuracy == .twentyMeters)
        #expect(context.service.locationSync.sendInterval == 10)
        #expect(context.location.maximumHorizontalAccuracy == 20)
        #expect(context.transport.prepareCount == 0)
        #expect(!context.location.isRunning)
    }
}
