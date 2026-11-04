import Foundation

struct NikonCameraStore {
    let defaults: UserDefaults
    private let key = "NSG.knownCameras.v1"

    /// Loads records at service initialization; missing or undecodable data yields an empty list without
    /// changing the system bond.
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
