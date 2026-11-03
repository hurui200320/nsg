import Foundation
import CoreBluetooth
import Testing
@testable import NSG

@MainActor
struct NikonAutoReconnectTests {
    private func camera(connectedAt: Date?) -> NikonCameraRecord {
        let id = UUID()
        return NikonCameraRecord(
            id: id, peripheralIdentifier: id, name: "Z5",
            controllerDevice: 1, controllerNonce: 42,
            pairingCompletedAt: Date(), lastConnectedAt: connectedAt
        )
    }

    @Test("On upgrade, select only the most recently connected camera with a successful connection")
    func migration() throws {
        let suite = "NSGTests.autoReconnect.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let older = camera(connectedAt: Date(timeIntervalSince1970: 100))
        let latest = camera(connectedAt: Date(timeIntervalSince1970: 200))
        let pairedOnly = camera(connectedAt: nil)
        try NikonCameraStore(defaults: defaults).save([older, pairedOnly, latest])
        let service = BluetoothService(defaults: defaults)
        #expect(service.automaticReconnectCameraID == latest.id)
        #expect(service.isAutomaticReconnectEnabled)
        // Initialization does not request Bluetooth permission; AppView's start button still calls prepare.
        #expect(service.central == nil)
    }

    @Test("Manual disconnection stays disabled across service recreation; selecting a camera restores reconnection")
    func manualCancellationPersists() throws {
        let suite = "NSGTests.autoReconnect.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let target = camera(connectedAt: Date())
        try NikonCameraStore(defaults: defaults).save([target])
        let service = BluetoothService(defaults: defaults)
        service.bluetoothState = .poweredOn
        #expect(service.shouldAutomaticallyReconnect)
        service.disconnect()
        #expect(!service.isAutomaticReconnectEnabled)
        #expect(!service.shouldAutomaticallyReconnect)
        let restored = BluetoothService(defaults: defaults)
        restored.bluetoothState = .poweredOn
        #expect(restored.automaticReconnectCameraID == target.id)
        #expect(!restored.shouldAutomaticallyReconnect)
        restored.enableAutomaticReconnection(for: target.id)
        #expect(restored.shouldAutomaticallyReconnect)
        let enabledAgain = BluetoothService(defaults: defaults)
        #expect(enabledAgain.isAutomaticReconnectEnabled)
        enabledAgain.disableAutomaticReconnection()
    }

    @Test("Unexpected failures preserve reconnection intent; cancellation clears the backoff task")
    func failureAndCancellation() async throws {
        let suite = "NSGTests.autoReconnect.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let target = camera(connectedAt: Date())
        try NikonCameraStore(defaults: defaults).save([target])
        let service = BluetoothService(defaults: defaults)
        service.bluetoothState = .poweredOn
        service.fail("Simulated unexpected disconnection")
        let task = try #require(service.automaticReconnectTask)
        #expect(service.connectionState == .waitingToReconnect)
        #expect(service.isAutomaticReconnectEnabled)
        #expect(service.automaticReconnectAttemptCount == 1)
        service.disconnect()
        await Task.yield()
        #expect(task.isCancelled)
        #expect(service.automaticReconnectTask == nil)
        #expect(service.automaticReconnectTaskID == nil)
        #expect(service.reconnectionTarget == nil)
        #expect(service.connectionState == .disconnected)
        #expect(service.central == nil)
        #expect(!service.isAutomaticReconnectEnabled)
    }

    @Test("System disconnection pauses retries without losing intent; do not start parallel reconnections while busy")
    func eligibility() throws {
        let suite = "NSGTests.autoReconnect.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let target = camera(connectedAt: Date())
        try NikonCameraStore(defaults: defaults).save([target])
        let service = BluetoothService(defaults: defaults)
        service.bluetoothState = .poweredOff
        #expect(!service.shouldAutomaticallyReconnect)
        #expect(service.isAutomaticReconnectEnabled)
        service.bluetoothState = .poweredOn
        #expect(service.shouldAutomaticallyReconnect)
        service.connectionState = .handshaking
        #expect(!service.shouldAutomaticallyReconnect)
        service.connectionState = .showingPairingPicker
        #expect(!service.shouldAutomaticallyReconnect)
        service.connectionState = .reconnecting
        #expect(!service.shouldAutomaticallyReconnect)
        service.connectionState = .failed("Temporarily unavailable")
        #expect(service.shouldAutomaticallyReconnect)
    }

    @Test("Stopping reconnection scanning counts as explicit cancellation; removing a camera does not fall back to other devices")
    func stopAndForget() throws {
        let suite = "NSGTests.autoReconnect.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let target = camera(connectedAt: Date())
        let other = camera(connectedAt: Date(timeIntervalSince1970: 1))
        try NikonCameraStore(defaults: defaults).save([other, target])
        let service = BluetoothService(defaults: defaults)
        service.reconnectionTarget = target
        service.connectionState = .reconnecting
        service.stopScan()
        #expect(!service.isAutomaticReconnectEnabled)
        service.enableAutomaticReconnection(for: target.id)
        service.forgetCamera(target)
        let restored = BluetoothService(defaults: defaults)
        restored.bluetoothState = .poweredOn
        #expect(restored.knownCameras == [other])
        #expect(!restored.shouldAutomaticallyReconnect)
    }

    @Test("Backoff increases and is capped at one minute")
    func retryDelays() {
        #expect((1...6).map { BluetoothService.automaticReconnectDelay(attempt: $0) }
            == [5, 10, 20, 40, 60, 60])
        #expect(BluetoothService.automaticReconnectDelay(attempt: Int.max) == 60)
        #expect(BluetoothService.automaticReconnectDelay(attempt: 0) == 5)
    }
}
