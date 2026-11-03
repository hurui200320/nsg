import Foundation
import ExternalAccessory

// Public iOS system UI. Only accessories advertising the iAP-over-Bluetooth
// identifier are eligible; a successful return alone does not verify Nikon GEO.
enum NikonAccessoryPicker {
    enum Outcome: Sendable {
        case completed
        case alreadyConnected
        case cancelled
        case notFound(String)
        case failed(String)
        case simulatorUnavailable
    }

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
