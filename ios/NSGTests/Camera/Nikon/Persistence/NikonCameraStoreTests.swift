import Foundation
import Testing

@testable import NSG

@MainActor
struct NikonCameraStoreTests {
    @Test("Camera records round-trip with their identity and updated connection metadata")
    func cameraRecordRoundTripPreservesIDAndUpdatedMetadata() throws {
        let suiteName = "NSGTests.cameras.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let original = CameraTestContext.camera()
        var updated = original
        updated.peripheralIdentifier = UUID()
        updated.lastConnectedAt = Date(timeIntervalSince1970: 200)
        let store = NikonCameraStore(defaults: defaults)
        try store.save([updated])
        #expect(store.load() == [updated])
    }
}
