import Foundation
import Testing

@testable import NSG

@MainActor
struct NikonAutoReconnectStoreTests {
    @Test("Pairing-only records do not become an automatic reconnect target")
    func migrationRequiresSuccessfulConnection() throws {
        let suiteName = "NSGTests.reconnect.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cameras = [CameraTestContext.camera()]

        let preference = NikonAutoReconnectStore(defaults: defaults).load(knownCameras: cameras)

        #expect(preference == NikonAutoReconnectPreference(cameraID: nil, isEnabled: false))
    }
}
