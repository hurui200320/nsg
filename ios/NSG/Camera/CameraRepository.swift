import Foundation

/// Application access to cameras, identities, and reconnect preferences; preserves existing storage keys and
/// formats.
struct CameraRepository {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    func loadCameras() -> [NikonCameraRecord] { NikonCameraStore(defaults: defaults).load() }

    func saveCameras(_ cameras: [NikonCameraRecord]) throws {
        try NikonCameraStore(defaults: defaults).save(cameras)
    }

    func loadReconnectPreference(cameras: [NikonCameraRecord]) -> NikonAutoReconnectPreference {
        NikonAutoReconnectStore(defaults: defaults).load(knownCameras: cameras)
    }

    func saveReconnectPreference(_ preference: NikonAutoReconnectPreference) {
        NikonAutoReconnectStore(defaults: defaults).save(preference)
    }

    /// Resolves identity before connection; verified targets reuse saved identity and bind the new UUID, while
    /// unknown devices resolve by UUID.
    func identity(for device: CameraDevice, camera: NikonCameraRecord?,
                  knownCameras: [NikonCameraRecord]) -> NikonControllerIdentity {
        let identities = NikonIdentityStore(defaults: defaults)
        if let camera {
            // The stable saved record is authoritative even when an old UUID alias is missing.
            identities.associate(camera.identity, identifier: device.id)
            return camera.identity
        }
        return identities.resolve(identifier: device.id, excluding: Set(knownCameras.map(\.controllerDevice)))
    }
}
