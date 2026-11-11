import Foundation
import Testing

@testable import NSG

@MainActor
struct NikonCameraRepositoryTests {
    @Test("New cameras with the same name receive independent controller identities")
    func sameNamedCamerasDoNotReuseLegacyNameIdentity() throws {
        let suiteName = "NSGTests.identity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = NikonPairingMessage(stage: 1, timestamp: 0, device: 1, nonce: 42)
        defaults.set(legacy.data, forKey: "NikonProbe.cameraIdentity.Z5")
        let repository = NikonCameraRepository(defaults: defaults)
        let first = repository.identity(
            for: CameraDevice(id: UUID(), name: "Z5"),
            camera: nil,
            knownCameras: []
        )
        let second = repository.identity(
            for: CameraDevice(id: UUID(), name: "Z5"),
            camera: nil,
            knownCameras: []
        )
        #expect(first != second)
        #expect(first.stage1Identity != legacy)
        #expect(second.stage1Identity != legacy)
    }

    @Test("Saved records restore the original identity when a transport UUID alias is missing")
    func savedCameraIdentityBindsNewPeripheralAlias() throws {
        let suiteName = "NSGTests.cameras.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let target = CameraTestContext.camera()
        let device = CameraDevice(id: UUID(), name: target.name)
        let restored = NikonCameraRepository(defaults: defaults).identity(
            for: device,
            camera: target,
            knownCameras: [target]
        )
        #expect(restored == target.identity)
        #expect(NikonIdentityStore(defaults: defaults).identity(for: device.id) == target.identity)
    }
}
