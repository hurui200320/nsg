import CoreBluetooth
import Foundation
import Testing

@testable import NSG

@MainActor
struct NikonCameraServiceTests {
    @Test("Visible discovery pauses only during connecting and continues after connection")
    func visibleDiscoveryPausesWhileConnectingAndResumesDuringDiscovery() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        context.service.setDiscoveryVisible(true)
        context.transport.emit(.stateChanged(.poweredOn))
        #expect(context.service.isScanning)

        let device = CameraDevice(id: UUID(), name: "Z5")
        context.transport.emit(.discovered(device, nil))
        context.service.connect(device)
        let session = try #require(context.transport.connections.last?.sessionID)
        #expect(context.service.connectionState == .connecting)
        #expect(!context.service.isScanning)

        context.transport.emit(.discovering(session))
        #expect(context.service.isScanning)
        #expect(context.service.devices.contains(where: { $0.id == device.id }))
        context.transport.emit(.connected(session, CameraTestContext.capabilities))
        context.transport.emit(.subscriptionChanged(session, .pairing, true, nil))
        context.transport.emit(.subscriptionChanged(session, .success, true, nil))
        context.finishHandshake(session)
        #expect(context.service.connectionState == .ready)
        #expect(context.service.isScanning)

        let other = CameraDevice(id: UUID(), name: "Z6")
        context.transport.emit(.discovered(other, nil))
        #expect(context.service.devices.contains(where: { $0.id == other.id }))
        context.service.setDiscoveryVisible(false)
        #expect(!context.service.isScanning)
        #expect(context.service.connectionState == .ready)
    }

    @Test("Persist known cameras and restore them when the service initializes")
    func serviceRestoresSavedCamerasAndPersistsForget() throws {
        let suiteName = "NSGTests.cameras.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let target = CameraTestContext.camera()
        let store = NikonCameraStore(defaults: defaults)
        try store.save([target])
        #expect(store.load() == [target])
        let service = NikonCameraService(defaults: defaults, transport: FakeCameraTransport())
        #expect(service.knownCameras == [target])
        service.forgetCamera(target)
        #expect(store.load().isEmpty)
    }

    @Test("Cancelling the handshake cancels both operation and delayed-name timers")
    func disconnectCancelsHandshakeAndDelayedNameTimers() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        let session = try context.connect()
        context.transport.emit(.writeCompleted(session, .pairing, nil))
        context.transport.emit(.valueReceived(session, .pairing, CameraTestContext.stage2.data))
        context.transport.emit(.writeCompleted(session, .pairing, nil))
        context.transport.emit(.valueReceived(session, .pairing, CameraTestContext.stage4.data))
        context.service.disconnect()
        context.scheduler.advance(by: 60)
        #expect(context.transport.writes(to: .controllerName).isEmpty)
        #expect(context.transport.disconnections == [session])
    }

    @Test("Incompatible handshake capabilities fail before any pairing writes")
    func incompatibleCapabilitiesFailBeforeHandshake() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        var properties = CameraTestContext.capabilities.properties
        properties.removeValue(forKey: .pairing)

        let session = try context.connect(
            capabilities: NikonCameraCapabilities(properties: properties, maximumWriteLength: 512)
        )

        #expect(context.service.lastFailure?.recovery == .userAction)
        #expect(!context.service.canSendLocation)
        #expect(context.transport.subscriptions.isEmpty)
        #expect(context.transport.writes.isEmpty)
        #expect(context.transport.disconnections == [session])
    }

    @Test("A camera without writable GEO can become ready but cannot receive location")
    func handshakeWithoutGeoDoesNotAllowLocationSending() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        var properties = CameraTestContext.capabilities.properties
        properties.removeValue(forKey: .location)
        let session = try context.connect(
            capabilities: NikonCameraCapabilities(properties: properties, maximumWriteLength: 512)
        )

        context.finishHandshake(session)
        context.location.emit(context.fix())
        context.service.sendCurrentLocation()

        #expect(context.service.connectionState == .ready)
        #expect(!context.service.canSendLocation)
        #expect(context.transport.writes(to: .location).isEmpty)
    }

    @Test("Stage 2 timeout performs one recovery read then disconnects if the camera remains silent")
    func stage2TimeoutReadsOnceThenDisconnects() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        let session = try context.connect()
        context.transport.emit(.writeCompleted(session, .pairing, nil))

        context.scheduler.advance(by: 15)
        #expect(context.transport.reads == [.pairing])
        #expect(context.transport.disconnections.isEmpty)

        context.scheduler.advance(by: 5)
        #expect(context.transport.reads == [.pairing])
        #expect(context.transport.disconnections == [session])
        #expect(context.service.lastFailure?.message.contains("Reading Stage 2 timed out") == true)
    }

    @Test("Missing NOT1 triggers the name write after three seconds; its acknowledgement completes the handshake")
    func missingSuccessNotificationUsesDelayedNameWrite() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        let session = try context.connect()
        context.transport.emit(.writeCompleted(session, .pairing, nil))
        context.transport.emit(.valueReceived(session, .pairing, CameraTestContext.stage2.data))
        context.transport.emit(.writeCompleted(session, .pairing, nil))
        context.transport.emit(.valueReceived(session, .pairing, CameraTestContext.stage4.data))

        context.scheduler.advance(by: 2)
        #expect(context.transport.writes(to: .controllerName).isEmpty)
        context.scheduler.advance(by: 1)
        #expect(context.transport.writes(to: .controllerName) == [NikonHandshake.controllerNameData])
        #expect(context.service.connectionState == .handshaking)

        context.transport.emit(.writeCompleted(session, .controllerName, nil))
        #expect(context.service.connectionState == .ready)
        context.scheduler.advance(by: 15)
        #expect(context.transport.disconnections.isEmpty)
    }
}
