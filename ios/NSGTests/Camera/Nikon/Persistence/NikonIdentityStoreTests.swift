import Foundation
import Testing

@testable import NSG

@MainActor
struct NikonIdentityStoreTests {
    @Test("Preserve controller identity after camera reconnection and peripheral UUID changes")
    func resolvedIdentitySurvivesStoreRecreationAndUUIDChanges() throws {
        let suiteName = "NSGTests.identity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NikonIdentityStore(defaults: defaults)
        let identifier = UUID()
        let first = store.resolve(identifier: identifier)
        let reconnected = NikonIdentityStore(defaults: defaults).resolve(identifier: identifier)
        let changedIdentifier = UUID()
        store.associate(first, identifier: changedIdentifier)
        let changedUUID = store.resolve(identifier: changedIdentifier)
        #expect(first == reconnected)
        #expect(first == changedUUID)
        #expect(NikonIdentityStore(defaults: defaults).identity(for: changedIdentifier) == first)
        #expect(first.device & 0xFF == 1)
    }

    @Test("Reject arbitrary migration to a system peripheral when multiple legacy identities exist")
    func legacyMigrationRejectsAmbiguousIdentities() throws {
        let suiteName = "NSGTests.identity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for device: UInt32 in [1, 257] {
            let message = NikonPairingMessage(stage: 1, timestamp: 0, device: device, nonce: 42)
            defaults.set(message.data, forKey: "NikonProbe.identity.\(UUID().uuidString)")
        }
        let store = NikonIdentityStore(defaults: defaults)
        #expect(throws: NikonIdentityError.ambiguousIdentity) {
            _ = try store.migrateLegacyIdentity(to: UUID())
        }
    }
}
