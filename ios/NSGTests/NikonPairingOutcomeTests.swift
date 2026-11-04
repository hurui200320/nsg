import Foundation
import CoreBluetooth
import Testing
@testable import NSG

@MainActor
struct NikonPairingOutcomeTests {
    @Test("System pairing success saves the target and reconnects without another confirmation",
          arguments: [NikonAccessoryPicker.Outcome.completed, .alreadyConnected])
    func successReconnectsAutomatically(outcome: NikonAccessoryPicker.Outcome) async throws {
        var pickerCount = 0
        let context = try CameraTestContext(picker: {
            pickerCount += 1
            return outcome
        })
        defer { context.cleanup() }
        let session = try context.connect(firstPairing: true)
        let device = try #require(context.transport.connections.last?.0)
        context.finishHandshake(session)
        #expect(context.service.connectionState == .disconnectingForPairing)
        #expect(context.service.knownCameras.isEmpty)
        context.transport.emit(.disconnected(session, nil))
        for _ in 0..<100 where context.service.isPairingPickerPresented { await Task.yield() }

        #expect(context.service.connectionState == .reconnecting)
        let saved = try #require(context.service.knownCameras.first)
        #expect(saved.peripheralIdentifier == device.id)
        #expect(NikonCameraStore(defaults: context.defaults).load() == [saved])
        #expect(context.service.automaticReconnectCameraID == saved.id)
        #expect(context.service.isAutomaticReconnectEnabled)
        #expect(context.transport.scans == [.reconnection])

        context.transport.emit(.discovered(device, nil))
        let reconnectedSession = try #require(context.transport.connections.last?.1)
        #expect(reconnectedSession != session)
        context.transport.emit(.discovering(reconnectedSession))
        context.transport.emit(.connected(reconnectedSession, CameraCapabilities(properties: [
            .pairing: [.write, .indicate, .read], .success: [.notify],
            .controllerName: [.write], .location: [.write]
        ], maximumWriteLength: 512)))
        context.transport.emit(.subscriptionChanged(reconnectedSession, .pairing, true, nil))
        context.transport.emit(.subscriptionChanged(reconnectedSession, .success, true, nil))
        context.finishHandshake(reconnectedSession)
        #expect(context.service.connectionState == .ready)
        #expect(context.service.knownCameras.first?.lastConnectedAt != nil)
        #expect(context.transport.disconnections == [session])
        #expect(pickerCount == 1)
    }

    @Test("An uncertain picker result waits for camera confirmation before saving or reconnecting")
    func targetConfirmation() async throws {
        let context = try CameraTestContext(picker: { .notFound("not found") })
        defer { context.cleanup() }
        let session = try context.connect(firstPairing: true)
        context.finishHandshake(session)
        context.transport.emit(.disconnected(session, nil))
        for _ in 0..<100 where context.service.isPairingPickerPresented { await Task.yield() }
        #expect(context.service.connectionState == .pairingNeedsConfirmation("not found"))
        #expect(context.service.knownCameras.isEmpty)
        #expect(NikonCameraStore(defaults: context.defaults).load().isEmpty)
        #expect(context.transport.scans.isEmpty)
        context.service.confirmPairingOnCamera()
        #expect(context.service.knownCameras.count == 1)
        #expect(context.service.connectionState == .reconnecting)
    }

    @Test("Cancellation cannot save a target or start reconnection")
    func cancelledDoesNotRecover() async throws {
        let context = try CameraTestContext(picker: { .cancelled })
        defer { context.cleanup() }
        let session = try context.connect(firstPairing: true)
        context.finishHandshake(session)
        context.transport.emit(.disconnected(session, nil))
        for _ in 0..<100 where context.service.isPairingPickerPresented { await Task.yield() }
        #expect(context.service.connectionState == .disconnected)
        context.service.confirmPairingOnCamera()
        #expect(context.service.knownCameras.isEmpty)
        #expect(context.transport.scans.isEmpty)
    }
}
