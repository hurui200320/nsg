import Foundation

/// Camera identity and pairing data; held temporarily while the system pairing picker is open.
struct NikonCameraRecord: Codable, Equatable, Identifiable {
    /// Immutable record ID used for UI selection and automatic reconnect preferences.
    let id: UUID
    /// Most recently connected peripheral UUID; may change between sessions and is updated after successful
    /// reconnection.
    var peripheralIdentifier: UUID
    var name: String?
    let controllerDevice: UInt32
    let controllerNonce: UInt32
    var pairingCompletedAt: Date
    /// Last successful BLE handshake time; remains nil if only system pairing has completed.
    var lastConnectedAt: Date?

    var identity: NikonControllerIdentity {
        NikonControllerIdentity(device: controllerDevice, nonce: controllerNonce)
    }
}
