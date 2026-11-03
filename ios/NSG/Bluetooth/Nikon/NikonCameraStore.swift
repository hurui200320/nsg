import Foundation

/// A target record returned by the system dialog; it does not independently verify GEO support or the system bond.
struct NikonCameraRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var peripheralIdentifier: UUID
    var name: String?
    let controllerDevice: UInt32
    let controllerNonce: UInt32
    var pairingCompletedAt: Date
    var lastConnectedAt: Date?

    var identity: NikonPairingMessage {
        NikonPairingMessage(stage: 1, timestamp: 0, device: controllerDevice, nonce: controllerNonce)
    }
}

struct NikonCameraStore {
    let defaults: UserDefaults
    private let key = "NSG.knownCameras.v1"

    func load() -> [NikonCameraRecord] {
        guard let data = defaults.data(forKey: key),
              let cameras = try? JSONDecoder().decode([NikonCameraRecord].self, from: data) else {
            return []
        }
        return cameras
    }

    func save(_ cameras: [NikonCameraRecord]) throws {
        defaults.set(try JSONEncoder().encode(cameras), forKey: key)
    }
}

/// Match only by UUID or Nikon manufacturer advertisement data; never connect automatically by name.
enum NikonCameraMatcher {
    static func matches(
        _ target: NikonCameraRecord,
        identifier: UUID,
        manufacturerData: Data?,
        knownCameras: [NikonCameraRecord]
    ) -> Bool {
        if identifier == target.peripheralIdentifier { return true }
        guard let manufacturerData else { return false }
        let bytes = Array(manufacturerData)
        guard bytes.count >= 7, bytes[0] == 0x99, bytes[1] == 0x03 else { return false }
        let device = (0..<4).reduce(UInt32(0)) {
            $0 | UInt32(bytes[$1 + 2]) << ($1 * 8)
        }
        // Advertisements contain only a 32-bit device value. Reject automatic selection if local records conflict.
        let matches = knownCameras.filter { $0.controllerDevice == device }
        return device == target.controllerDevice &&
            matches.count == 1 && matches.first?.id == target.id
    }
}
