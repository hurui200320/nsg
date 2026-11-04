import Foundation
import ExternalAccessory

/// Adapter for the system accessory picker; shows iAP-over-Bluetooth accessories but does not identify the
/// camera selected.
enum NikonAccessoryPicker {
    enum Outcome: Sendable {
        case completed
        case alreadyConnected
        case cancelled
        case notFound(String)
        case failed(String)
        case simulatorUnavailable
    }

    /// Called after initial BLE handshake and disconnection; returns the system outcome after picker dismissal.
    /// The caller reconnects on success and may request camera confirmation for uncertain results.
    @MainActor
    static func present() async -> Outcome {
        #if targetEnvironment(simulator)
        return .simulatorUnavailable
        #else
        do {
            // Do not filter names: the Classic name may differ from the BLE name.
            // The person must select their camera and confirm the system passkey.
            try await EAAccessoryManager.shared().showBluetoothAccessoryPicker(withNameFilter: nil)
            return .completed
        } catch {
            let value = error as NSError
            let detail = "\(value.domain) code=\(value.code)：\(value.localizedDescription)"
            guard value.domain == EABluetoothAccessoryPickerErrorDomain,
                  let code = EABluetoothAccessoryPickerError.Code(rawValue: value.code) else {
                return .failed(detail)
            }
            switch code {
            case .alreadyConnected: return .alreadyConnected
            case .resultCancelled: return .cancelled
            case .resultNotFound: return .notFound(detail)
            case .resultFailed: return .failed(detail)
            @unknown default: return .failed(detail)
            }
        }
        #endif
    }
}
