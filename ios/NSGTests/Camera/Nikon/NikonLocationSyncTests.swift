import CoreBluetooth
import Foundation
import Testing

@testable import NSG

@MainActor
struct NikonLocationSyncTests {
    @Test("Automatic sends are throttled; manual sends bypass only the interval")
    func manualSendBypassesAutomaticInterval() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        let session = try context.connect()
        context.finishHandshake(session)
        #expect(context.location.isRunning)
        context.location.emit(context.fix())
        #expect(context.transport.writes(to: .location).count == 1)
        context.transport.emit(.writeCompleted(session, .location, nil))
        context.scheduler.advance(by: 9)
        context.location.emit(context.fix())
        #expect(context.transport.writes(to: .location).count == 1)
        context.service.sendCurrentLocation()
        #expect(context.transport.writes(to: .location).count == 2)
        context.transport.emit(.writeCompleted(session, .location, nil))
        context.scheduler.advance(by: 10)
        context.location.emit(context.fix())
        #expect(context.transport.writes(to: .location).count == 3)
    }

    @Test("Stopping and restarting GPS preserves an in-flight write until acknowledgement")
    func restartingGPSPreservesInFlightWriteUntilAcknowledgement() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        let session = try context.connect()
        context.finishHandshake(session)
        context.location.emit(context.fix())
        context.services.setLocationEnabled(false)
        context.services.setLocationEnabled(true)
        context.location.emit(context.fix())
        #expect(context.transport.writes(to: .location).count == 1)
        context.transport.emit(.writeCompleted(session, .location, nil))
        #expect(context.service.locationTransferState == .sent)
        context.scheduler.advance(by: 15)
        #expect(context.transport.disconnections.isEmpty)
    }

    @Test("ATT 0x80 retains its error and disconnects for a new handshake")
    func attRejectionDisconnectsAndSchedulesNewHandshake() throws {
        let target = CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 200))
        let context = try CameraTestContext(cameras: [target])
        defer { context.cleanup() }

        context.transport.emit(.stateChanged(.poweredOn))
        let device = CameraDevice(id: target.peripheralIdentifier, name: target.name)
        context.transport.emit(.discovered(device, nil))
        let session = try #require(context.transport.connections.last?.sessionID)
        context.discoverAndSubscribe(session)
        context.finishHandshake(session)
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
    func writeTimeoutDisconnectsAndIgnoresLateAcknowledgement() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        let session = try context.connect()
        context.finishHandshake(session)
        context.location.emit(context.fix())
        context.scheduler.advance(by: 15)
        #expect(context.transport.disconnections == [session])
        guard case .failed = context.service.locationTransferState else {
            Issue.record("Expected GPS timeout")
            return
        }
        context.transport.emit(.disconnected(session, nil))
        context.transport.emit(.writeCompleted(session, .location, nil))
        #expect(context.service.lastLocationSentAt == nil)
        #expect(context.location.isRunning)
    }
}
