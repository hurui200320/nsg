import Foundation
import Testing

@testable import NSG

@MainActor
struct NikonPairingTests {
    @Test(
        "Successful or not-found picker results save the target and reconnect without another confirmation",
        arguments: [NikonAccessoryPicker.Outcome.completed, .alreadyConnected, .notFound("not found")]
    )
    func acceptedPickerResultSavesCameraAndReconnectsOnce(outcome: NikonAccessoryPicker.Outcome) async throws {
        var pickerCount = 0
        let context = try CameraTestContext(picker: {
            pickerCount += 1
            return outcome
        })
        defer { context.cleanup() }

        let session = try context.connect(firstPairing: true)
        let device = try #require(context.transport.connections.last?.device)
        context.finishHandshake(session)
        #expect(context.service.connectionState == .disconnectingForPairing)
        #expect(context.service.knownCameras.isEmpty)
        context.transport.emit(.disconnected(session, nil))
        try await waitUntil { !context.service.isPairingPickerPresented }

        #expect(context.service.connectionState == .reconnecting)
        let saved = try #require(context.service.knownCameras.first)
        #expect(saved.peripheralIdentifier == device.id)
        #expect(NikonCameraStore(defaults: context.defaults).load() == [saved])
        #expect(context.service.automaticReconnectCameraID == saved.id)
        #expect(context.service.isAutomaticReconnectEnabled)
        #expect(context.transport.scans == [.reconnection])

        context.transport.emit(.discovered(device, nil))
        let reconnectedSession = try #require(context.transport.connections.last?.sessionID)
        #expect(reconnectedSession != session)
        context.discoverAndSubscribe(reconnectedSession)
        context.finishHandshake(reconnectedSession)
        #expect(context.service.connectionState == .ready)
        #expect(context.service.knownCameras.first?.lastConnectedAt != nil)
        #expect(context.transport.disconnections == [session])
        #expect(pickerCount == 1)
    }

    @Test("Cancellation cannot save a target or start reconnection")
    func cancelledPairingDoesNotSaveOrReconnect() async throws {
        let context = try CameraTestContext(picker: { .cancelled })
        defer { context.cleanup() }

        let session = try context.connect(firstPairing: true)
        context.finishHandshake(session)
        context.transport.emit(.disconnected(session, nil))
        try await waitUntil { !context.service.isPairingPickerPresented }
        #expect(context.service.connectionState == .disconnected)
        #expect(context.service.knownCameras.isEmpty)
        #expect(context.transport.scans.isEmpty)
    }

    @Test(
        "Failed or unavailable system pairing requires user action without saving a camera",
        arguments: [NikonAccessoryPicker.Outcome.failed("Picker failed"), .simulatorUnavailable]
    )
    func unsuccessfulPickerRequiresUserAction(_ outcome: NikonAccessoryPicker.Outcome) async throws {
        let context = try CameraTestContext(picker: { outcome })
        defer { context.cleanup() }

        let session = try context.connect(firstPairing: true)
        context.finishHandshake(session)
        context.transport.emit(.disconnected(session, nil))

        try await waitUntil { !context.service.isPairingPickerPresented }

        #expect(context.service.lastFailure?.recovery == .userAction)
        #expect(context.service.knownCameras.isEmpty)
        #expect(NikonCameraStore(defaults: context.defaults).load().isEmpty)
        #expect(!context.service.shouldAutomaticallyReconnect)
        context.scheduler.advance(by: 120)
        #expect(context.transport.scans.isEmpty)
    }
}
