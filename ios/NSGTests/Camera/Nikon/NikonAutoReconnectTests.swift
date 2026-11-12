import CoreBluetooth
import Foundation
import Testing

@testable import NSG

@MainActor
struct NikonAutoReconnectTests {
    @Test("Upgrade selects the most recently connected camera without preparing Bluetooth")
    func initializationSelectsLatestConnectedCameraWithoutPreparingBluetooth() throws {
        let older = CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 100))
        let latest = CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 200))
        let context = try CameraTestContext(cameras: [older, CameraTestContext.camera(), latest])
        defer { context.cleanup() }

        #expect(context.service.automaticReconnectCameraID == latest.id)
        #expect(context.service.isAutomaticReconnectEnabled)
        #expect(context.transport.prepareCount == 0)
    }

    @Test("Manual disconnect persists disabled reconnection; selecting the camera restores it")
    func manualDisconnectPersistsDisabledReconnectUntilCameraIsSelected() throws {
        let target = CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 200))
        let context = try CameraTestContext(cameras: [target])
        defer { context.cleanup() }

        context.transport.emit(.stateChanged(.poweredOn))
        #expect(context.transport.scans.count == 1)
        context.service.disconnect()
        #expect(!NikonAutoReconnectStore(defaults: context.defaults).load(knownCameras: [target]).isEnabled)
        let restored = NikonCameraService(
            defaults: context.defaults,
            transport: FakeCameraTransport(),
            scheduler: context.scheduler,
            locationSource: FakeLocationSource()
        )
        #expect(!restored.isAutomaticReconnectEnabled)
        #expect(restored.automaticReconnectCameraID == target.id)

        context.service.connectKnownCamera(target)
        #expect(context.service.isAutomaticReconnectEnabled)
        #expect(context.transport.scans.count == 2)
    }

    @Test("Timeout preserves its cause during backoff and cancellation prevents later attempts")
    func rediscoveryTimeoutRetainsFailureAndCancellationStopsRetry() throws {
        let context = try CameraTestContext(cameras: [
            CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 200))
        ])
        defer { context.cleanup() }

        context.transport.emit(.stateChanged(.poweredOn))
        context.scheduler.advance(by: 30)
        #expect(context.service.connectionState == .waitingToReconnect)
        #expect(context.service.lastFailure?.message.contains("rediscovery timed out") == true)
        context.scheduler.advance(by: 4)
        #expect(context.transport.scans.count == 1)
        context.service.disconnect()
        context.scheduler.advance(by: 120)
        #expect(context.transport.scans.count == 1)
        #expect(context.service.connectionState == .disconnected)
    }

    @Test("Bluetooth recovery resumes intent without parallel attempts")
    func bluetoothRecoveryDoesNotStartParallelReconnectAttempts() throws {
        let context = try CameraTestContext(cameras: [
            CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 200))
        ])
        defer { context.cleanup() }

        context.transport.emit(.stateChanged(.poweredOff))
        #expect(context.transport.scans.isEmpty)
        context.transport.emit(.stateChanged(.poweredOn))
        context.service.resumeAutomaticReconnection()
        #expect(context.transport.scans.count == 1)
        context.transport.emit(.stateChanged(.resetting))
        context.transport.emit(.stateChanged(.poweredOn))
        #expect(context.transport.scans.count == 1)
    }

    @Test("Forgetting the rediscovery target cancels retries and preserves other cameras")
    func forgettingReconnectTargetCancelsRetriesAndPreservesOtherCameras() throws {
        let target = CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 200))
        let other = CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 1), device: 257)
        let context = try CameraTestContext(cameras: [other, target])
        defer { context.cleanup() }

        context.transport.emit(.stateChanged(.poweredOn))
        context.service.forgetCamera(target)
        context.scheduler.advance(by: 120)
        #expect(context.service.knownCameras == [other])
        #expect(!context.service.shouldAutomaticallyReconnect)
        #expect(context.transport.scans == [.reconnection])
    }

    @Test("Verified manufacturer identity reconnects after a UUID change and updates the saved record")
    func reconnectionUpdatesPeripheralUUIDAndLastConnectedTime() throws {
        let target = CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 200))
        let context = try CameraTestContext(cameras: [target])
        defer { context.cleanup() }

        context.transport.emit(.stateChanged(.poweredOn))
        let device = CameraDevice(id: UUID(), name: target.name)
        context.transport.emit(.discovered(device, Data([0x99, 0x03, 1, 0x33, 0x22, 0x11, 0])))
        #expect(context.transport.connections.last?.device == device)
        #expect(context.service.connectionState == .connecting)

        let session = try #require(context.transport.connections.last?.sessionID)
        context.discoverAndSubscribe(session)
        context.finishHandshake(session)

        #expect(context.service.connectionState == .ready)
        let updated = try #require(context.service.knownCameras.first)
        #expect(updated.id == target.id)
        #expect(updated.identity == target.identity)
        #expect(updated.peripheralIdentifier == device.id)
        #expect(updated.lastConnectedAt == context.scheduler.now)
        #expect(NikonCameraStore(defaults: context.defaults).load() == [updated])
    }

    @Test("Late callbacks from a cancelled connection cannot alter the new connection")
    func callbacksFromOldSessionDoNotChangeCurrentHandshake() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        let old = try context.connect()
        context.service.disconnect()
        context.transport.emit(.disconnected(old, nil))
        let current = try context.connect()
        context.transport.emit(.disconnected(old, CameraFailure("Old disconnect")))
        context.transport.emit(.writeCompleted(old, .controllerName, nil))
        #expect(context.service.connectionState == .handshaking)
        context.finishHandshake(current)
        #expect(context.service.connectionState == .ready)
    }

    @Test("Stopping target scanning preserves saved camera records")
    func stoppingTargetScanPreservesSavedCameras() throws {
        let target = CameraTestContext.camera()
        let context = try CameraTestContext(cameras: [target])
        defer { context.cleanup() }

        context.transport.emit(.stateChanged(.poweredOn))
        context.service.connectKnownCamera(target)
        context.service.stopScan()
        context.scheduler.advance(by: 120)
        #expect(!context.service.isAutomaticReconnectEnabled)
        #expect(context.transport.scans.count == 1)
        #expect(context.service.connectionState == .disconnected)
        #expect(!context.service.isScanning)
        #expect(context.service.knownCameras == [target])
    }

    @Test("Rediscovery resumes at the scheduled retry deadline")
    func rediscoveryRetriesAfterBackoff() throws {
        let target = CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 200))
        let context = try CameraTestContext(cameras: [target])
        defer { context.cleanup() }

        context.transport.emit(.stateChanged(.poweredOn))
        context.scheduler.advance(by: 30)
        #expect(context.service.connectionState == .waitingToReconnect)

        context.scheduler.advance(by: 4)
        #expect(context.transport.scans == [.reconnection])
        context.scheduler.advance(by: 1)
        #expect(context.transport.scans == [.reconnection, .reconnection])
        #expect(context.service.connectionState == .reconnecting)

        let device = CameraDevice(id: target.peripheralIdentifier, name: target.name)
        context.transport.emit(.discovered(device, nil))
        #expect(context.transport.connections.last?.device == device)
    }

    @Test("A connection failure requiring user action does not schedule retries")
    func userActionFailureStopsAutomaticReconnect() throws {
        let target = CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 200))
        let context = try CameraTestContext(cameras: [target])
        defer { context.cleanup() }

        context.transport.emit(.stateChanged(.poweredOn))
        let device = CameraDevice(id: target.peripheralIdentifier, name: target.name)
        context.transport.emit(.discovered(device, nil))
        let session = try #require(context.transport.connections.last?.sessionID)
        let failure = CameraFailure("Camera requires pairing again.", recovery: .userAction)

        context.transport.emit(.failed(session, failure))
        context.transport.emit(.disconnected(session, nil))
        context.scheduler.advance(by: 120)

        #expect(context.service.lastFailure == failure)
        #expect(context.service.connectionState == .failed(failure.message))
        #expect(!context.service.shouldAutomaticallyReconnect)
        #expect(context.transport.scans == [.reconnection])
    }
}
