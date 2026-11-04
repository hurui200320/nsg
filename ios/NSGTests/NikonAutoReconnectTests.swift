import Foundation
import CoreBluetooth
import Testing
@testable import NSG

@MainActor
struct NikonAutoReconnectTests {
    @Test("Upgrade selects the most recently connected camera without preparing Bluetooth")
    func migration() throws {
        let older = CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 100))
        let latest = CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 200))
        let context = try CameraTestContext(cameras: [older, CameraTestContext.camera(), latest])
        defer { context.cleanup() }
        #expect(context.service.automaticReconnectCameraID == latest.id)
        #expect(context.service.isAutomaticReconnectEnabled)
        #expect(context.transport.prepareCount == 0)
    }

    @Test("Manual cancellation survives recreation and selecting a camera restores intent")
    func manualCancellationPersists() throws {
        let target = CameraTestContext.camera(connectedAt: Date())
        let context = try CameraTestContext(cameras: [target])
        defer { context.cleanup() }
        context.transport.emit(.stateChanged(.poweredOn))
        #expect(context.transport.scans.count == 1)
        context.service.disconnect()
        #expect(!NikonAutoReconnectStore(defaults: context.defaults).load(knownCameras: [target]).isEnabled)
        context.service.connectKnownCamera(target)
        #expect(context.service.isAutomaticReconnectEnabled)
        #expect(context.transport.scans.count == 2)
    }

    @Test("Timeout preserves its cause during backoff and cancellation prevents later attempts")
    func failureAndCancellation() throws {
        let context = try CameraTestContext(cameras: [CameraTestContext.camera(connectedAt: Date())])
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
    func eligibility() throws {
        let context = try CameraTestContext(cameras: [CameraTestContext.camera(connectedAt: Date())])
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

    @Test("Stopping target scanning or forgetting a camera cancels retries")
    func stopAndForget() throws {
        let target = CameraTestContext.camera(connectedAt: Date())
        let other = CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 1), device: 257)
        let context = try CameraTestContext(cameras: [other, target])
        defer { context.cleanup() }
        context.transport.emit(.stateChanged(.poweredOn))
        context.service.stopScan()
        #expect(!context.service.isAutomaticReconnectEnabled)
        context.service.connectKnownCamera(target)
        context.service.forgetCamera(target)
        context.scheduler.advance(by: 120)
        #expect(context.service.knownCameras == [other])
        #expect(!context.service.shouldAutomaticallyReconnect)
    }

    @Test("Retry uses five seconds initially, grows to one minute, and handles integer bounds")
    func retryDelays() {
        #expect((1...6).map { ReconnectPolicy.delay(attempt: $0) } == [5, 10, 20, 40, 60, 60])
        #expect(ReconnectPolicy.delay(attempt: Int.max) == 60)
        #expect(ReconnectPolicy.delay(attempt: Int.min) == 5)
    }

    @Test("An advertisement without a service UUID reconnects using its verified identity")
    func rediscoveryWithoutServiceUUID() throws {
        let target = CameraTestContext.camera(connectedAt: Date())
        let context = try CameraTestContext(cameras: [target])
        defer { context.cleanup() }
        context.transport.emit(.stateChanged(.poweredOn))
        let device = CameraDevice(id: UUID(), name: target.name)
        context.transport.emit(.discovered(device, Data([0x99, 0x03, 1, 0x33, 0x22, 0x11, 0])))
        #expect(context.transport.connections.last?.0 == device)
        #expect(context.service.connectionState == .connecting)
    }

    @Test("Late callbacks from a cancelled connection cannot alter the new connection")
    func staleCallbacks() throws {
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
}
