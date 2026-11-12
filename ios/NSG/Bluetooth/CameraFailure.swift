import Foundation
import CoreBluetooth

/// Shared failure description and recovery policy; preserves the underlying error domain and code across
/// retries.
struct CameraFailure: Error, Equatable, LocalizedError {
    enum Recovery { case retry, userAction }

    let message: String
    let domain: String?
    let code: Int?
    let recovery: Recovery

    init(_ message: String, recovery: Recovery = .retry) {
        self.message = message
        self.domain = nil
        self.code = nil
        self.recovery = recovery
    }

    init(error: Error, recovery: Recovery = .retry) {
        let value = error as NSError
        message = value.localizedDescription
        domain = value.domain
        code = value.code
        self.recovery = recovery
    }

    var errorDescription: String? { message }
    /// Checked after GEO write errors; Nikon ATT 0x80 rejection requires disconnection and a new handshake.
    var requiresGeoReconnection: Bool { domain == CBATTErrorDomain && code == 0x80 }

    var diagnosticDescription: String {
        guard let domain, let code else { return message }
        return "\(message) (\(domain), code \(code))"
    }
}
