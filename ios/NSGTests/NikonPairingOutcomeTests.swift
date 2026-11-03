import Foundation
import Testing
@testable import NSG

@MainActor
struct NikonPairingOutcomeTests {
    @Test("Keep the target and wait for confirmation when the system cannot find the accessory; do not save it as paired")
    func notFoundKeepsTarget() throws {
        let suite = "NSGTests.pairing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = BluetoothService(defaults: defaults)
        let identifier = UUID()
        let target = NikonCameraRecord(
            id: identifier, peripheralIdentifier: identifier, name: "Z5",
            controllerDevice: 1, controllerNonce: 42,
            pairingCompletedAt: Date(), lastConnectedAt: nil
        )
        service.pairingTarget = target
        service.connectionState = .showingPairingPicker
        service.handlePairingOutcome(.notFound("code=1"))
        #expect(service.connectionState == .pairingNeedsConfirmation("code=1"))
        #expect(service.pairingTarget == target)
        #expect(service.isPairing)
        #expect(service.knownCameras.isEmpty)
        #expect(NikonCameraStore(defaults: defaults).load().isEmpty)
        #expect(service.central == nil)

        service.disconnect()
        #expect(service.connectionState == .disconnected)
        #expect(service.pairingTarget == nil)
        #expect(service.knownCameras.isEmpty)
    }

    @Test("Cancelling system pairing does not enter the confirmation recovery flow")
    func cancelledDoesNotRecover() throws {
        let suite = "NSGTests.pairing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = BluetoothService(defaults: defaults)
        service.connectionState = .showingPairingPicker
        service.handlePairingOutcome(.cancelled)
        #expect(service.connectionState == .disconnected)
        service.confirmPairingOnCamera()
        #expect(service.knownCameras.isEmpty)
        #expect(service.central == nil)
    }
}
