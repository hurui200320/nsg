import Foundation
import CoreBluetooth

extension BluetoothService {
    var shouldAutomaticallyReconnect: Bool {
        guard isAutomaticReconnectEnabled,
              let cameraID = automaticReconnectCameraID,
              knownCameras.contains(where: { $0.id == cameraID }),
              bluetoothState == .poweredOn,
              activePeripheral == nil,
              !isPairingPickerPresented,
              pairingTarget == nil else { return false }
        switch connectionState {
        case .disconnected, .failed, .waitingToReconnect:
            return true
        default:
            return false
        }
    }

    func enableAutomaticReconnection(for cameraID: UUID) {
        cancelAutomaticReconnectTask()
        automaticReconnectCameraID = cameraID
        isAutomaticReconnectEnabled = true
        automaticReconnectAttemptCount = 0
        persistAutomaticReconnectPreference()
    }

    /// Keep reconnection disabled across launches after explicit cancellation; do not call for ordinary scan stops or system disconnections.
    func disableAutomaticReconnection() {
        cancelAutomaticReconnectTask()
        isAutomaticReconnectEnabled = false
        automaticReconnectAttemptCount = 0
        persistAutomaticReconnectPreference()
    }

    func persistAutomaticReconnectPreference() {
        NikonAutoReconnectStore(defaults: defaults).save(
            NikonAutoReconnectPreference(
                cameraID: automaticReconnectCameraID,
                isEnabled: isAutomaticReconnectEnabled
            )
        )
    }

    /// Call when Bluetooth recovers, the view reappears, or the app enters the foreground; do not duplicate an ongoing connection.
    @discardableResult
    func resumeAutomaticReconnection() -> Bool {
        guard shouldAutomaticallyReconnect else { return false }
        guard automaticReconnectTask == nil else { return true }
        beginAutomaticReconnectAttempt()
        return true
    }

    func beginAutomaticReconnectAttempt() {
        guard shouldAutomaticallyReconnect,
              let target = knownCameras.first(where: { $0.id == automaticReconnectCameraID }) else { return }
        startTargetReconnection(target)
    }

    static func automaticReconnectDelay(attempt: Int) -> Double {
        min(5 * pow(2, Double(min(max(attempt - 1, 0), 4))), 60)
    }

    func scheduleAutomaticReconnection() {
        guard shouldAutomaticallyReconnect, automaticReconnectTask == nil else { return }
        automaticReconnectAttemptCount = min(automaticReconnectAttemptCount + 1, 6)
        let delay = Self.automaticReconnectDelay(attempt: automaticReconnectAttemptCount)
        let token = UUID()
        automaticReconnectTaskID = token
        connectionState = .waitingToReconnect
        automaticReconnectTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, self.automaticReconnectTaskID == token else { return }
            self.automaticReconnectTask = nil
            self.automaticReconnectTaskID = nil
            self.beginAutomaticReconnectAttempt()
        }
    }

    func cancelAutomaticReconnectTask() {
        automaticReconnectTask?.cancel()
        automaticReconnectTask = nil
        automaticReconnectTaskID = nil
        if connectionState == .waitingToReconnect {
            connectionState = .disconnected
        }
    }
}
