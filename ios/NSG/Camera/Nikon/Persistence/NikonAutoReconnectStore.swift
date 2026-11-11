import Foundation

struct NikonAutoReconnectPreference: Equatable {
    var cameraID: UUID?
    var isEnabled: Bool
}

struct NikonAutoReconnectStore {
    let defaults: UserDefaults
    private let cameraKey = "NSG.autoReconnect.cameraID"
    private let enabledKey = "NSG.autoReconnect.enabled"

    /// Restores preferences at service initialization; without the new preference key, migrates only the most
    /// recently connected camera.
    func load(knownCameras: [NikonCameraRecord]) -> NikonAutoReconnectPreference {
        if defaults.object(forKey: enabledKey) != nil {
            return NikonAutoReconnectPreference(
                cameraID: defaults.string(forKey: cameraKey).flatMap(UUID.init(uuidString:)),
                isEnabled: defaults.bool(forKey: enabledKey)
            )
        }
        // When upgrading, migrate only cameras with a successful connection, not merely a completed pairing dialog.
        let latest = knownCameras.filter { $0.lastConnectedAt != nil }.max {
            ($0.lastConnectedAt ?? .distantPast) < ($1.lastConnectedAt ?? .distantPast)
        }
        return NikonAutoReconnectPreference(cameraID: latest?.id, isEnabled: latest != nil)
    }

    func save(_ preference: NikonAutoReconnectPreference) {
        defaults.set(preference.cameraID?.uuidString, forKey: cameraKey)
        defaults.set(preference.isEnabled, forKey: enabledKey)
    }
}
