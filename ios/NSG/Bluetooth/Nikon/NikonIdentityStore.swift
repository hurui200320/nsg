import Foundation

enum NikonProbeError: LocalizedError {
    case missingIdentity
    case ambiguousIdentity

    var errorDescription: String? {
        switch self {
        case .missingIdentity:
            return "No existing controller identity found. Connect through BLE scanning and complete the initial handshake first."
        case .ambiguousIdentity:
            return "Multiple legacy controller identities found. Connect once using the original BLE peripheral to identify the correct one."
        }
    }
}

// A system-connected GATT peripheral may have a different CoreBluetooth UUID.
// Preserve the protocol identity independently from that transport identifier.
struct NikonProbeIdentityStore {
    struct Resolution {
        let identity: NikonPairingMessage
        let detail: String
    }

    let defaults: UserDefaults

    func resolve(identifier: UUID, name: String?, systemConnected: Bool) throws -> Resolution {
        let uuidKey = "NikonProbe.identity.\(identifier.uuidString)"
        let nameKey = name.flatMap { $0.isEmpty ? nil : "NikonProbe.cameraIdentity.\($0)" }
        let identity: NikonPairingMessage
        let detail: String
        if let saved = decode(defaults.data(forKey: uuidKey)) {
            identity = saved
            detail = "Reusing the controller identity associated with the peripheral identifier"
        } else if let nameKey, let saved = decode(defaults.data(forKey: nameKey)) {
            identity = saved
            detail = "Peripheral identifier changed; reusing the existing controller identity by camera name"
        } else if systemConnected {
            // One-time migration from the earlier probe, which only saved UUID keys.
            // Never choose arbitrarily when multiple distinct identities exist.
            let records = defaults.dictionaryRepresentation()
            let legacy = Set(records.compactMap { key, value -> Data? in
                guard key.hasPrefix("NikonProbe.identity."), let data = value as? Data,
                      let identity = decode(data) else { return nil }
                return identity.data
            })
            guard !legacy.isEmpty else { throw NikonProbeError.missingIdentity }
            guard legacy.count == 1,
                  !records.keys.contains(where: { $0.hasPrefix("NikonProbe.cameraIdentity.") }),
                  let data = legacy.first, let saved = decode(data) else {
                throw NikonProbeError.ambiguousIdentity
            }
            identity = saved
            detail = "Migrating the sole legacy controller identity and associating it with the current camera name and new GATT identifier"
        } else {
            identity = NikonPairingMessage(stage: 1, timestamp: 0,
                device: (UInt32.random(in: .min ... .max) & 0xFFFFFF00) | 1,
                nonce: UInt32.random(in: .min ... .max))
            detail = "Generating and saving the controller identity"
        }
        defaults.set(identity.data, forKey: uuidKey)
        if let nameKey { defaults.set(identity.data, forKey: nameKey) }
        return Resolution(identity: identity, detail: detail)
    }

    func existingIdentity(identifier: UUID, name: String?) -> NikonPairingMessage? {
        if let saved = decode(defaults.data(forKey: "NikonProbe.identity.\(identifier.uuidString)")) {
            return saved
        }
        guard let name, !name.isEmpty else { return nil }
        return decode(defaults.data(forKey: "NikonProbe.cameraIdentity.\(name)"))
    }

    /// Call only after confirming the target identity; an advertised UUID change must not create a new identity.
    func associate(_ identity: NikonPairingMessage, identifier: UUID, name: String?) {
        defaults.set(identity.data, forKey: "NikonProbe.identity.\(identifier.uuidString)")
        if let name, !name.isEmpty {
            defaults.set(identity.data, forKey: "NikonProbe.cameraIdentity.\(name)")
        }
    }

    private func decode(_ data: Data?) -> NikonPairingMessage? {
        guard let data, let message = try? NikonPairingMessage(data: data), message.stage == 1 else {
            return nil
        }
        return message
    }
}

