import Foundation

/// Controller identity retained across reconnections; device helps match reconnect advertisements but is not a
/// unique camera identifier.
struct NikonControllerIdentity: Equatable {
    let device: UInt32
    let nonce: UInt32

    /// 17-byte identity representation for legacy storage; timestamp is a placeholder, so generate a fresh
    /// Stage 1 for each handshake.
    var stage1Identity: NikonPairingMessage {
        NikonPairingMessage(stage: 1, timestamp: 0, device: device, nonce: nonce)
    }
}

enum NikonIdentityError: LocalizedError {
    case missingIdentity
    case ambiguousIdentity

    var errorDescription: String? {
        switch self {
        case .missingIdentity: "No existing controller identity found."
        case .ambiguousIdentity: "Multiple legacy identities exist. Select and verify the original camera."
        }
    }
}

/// Stores identity aliases by peripheral UUID while retaining legacy keys and encoding; new cameras never
/// inherit identity by name.
struct NikonIdentityStore {
    let defaults: UserDefaults
    private let uuidPrefix = "NikonProbe.identity."
    private let namePrefix = "NikonProbe.cameraIdentity."

    func identity(for identifier: UUID) -> NikonControllerIdentity? {
        decode(defaults.data(forKey: uuidPrefix + identifier.uuidString))
    }

    /// Resolves an unknown device before connection; only newly generated device values exclude existing
    /// records to avoid matching conflicts.
    func resolve(identifier: UUID, excluding devices: Set<UInt32> = []) -> NikonControllerIdentity {
        if let saved = identity(for: identifier) { return saved }
        var device: UInt32
        repeat {
            device = (UInt32.random(in: .min ... .max) & 0xFFFFFF00) | 1
        } while devices.contains(device)
        let identity = NikonControllerIdentity(device: device, nonce: UInt32.random(in: .min ... .max))
        associate(identity, identifier: identifier)
        return identity
    }

    /// Binds saved identity to the current UUID after target matching or user verification; overwrites any
    /// existing alias for that UUID.
    func associate(_ identity: NikonControllerIdentity, identifier: UUID) {
        defaults.set(identity.stage1Identity.data, forKey: uuidPrefix + identifier.uuidString)
    }

    /// Explicit migration for a user-verified legacy camera; without a current alias, ambiguous history throws
    /// rather than matching by name.
    func migrateLegacyIdentity(to identifier: UUID) throws -> NikonControllerIdentity {
        if let saved = identity(for: identifier) { return saved }
        let encoded = Set(defaults.dictionaryRepresentation().compactMap { key, value -> Data? in
            guard key.hasPrefix(uuidPrefix) || key.hasPrefix(namePrefix),
                  let data = value as? Data, let identity = decode(data) else { return nil }
            return identity.stage1Identity.data
        })
        guard !encoded.isEmpty else { throw NikonIdentityError.missingIdentity }
        guard encoded.count == 1, let data = encoded.first, let identity = decode(data) else {
            throw NikonIdentityError.ambiguousIdentity
        }
        associate(identity, identifier: identifier)
        return identity
    }

    private func decode(_ data: Data?) -> NikonControllerIdentity? {
        guard let data, let message = try? NikonPairingMessage(data: data), message.stage == 1 else { return nil }
        return NikonControllerIdentity(device: message.device, nonce: message.nonce)
    }
}
