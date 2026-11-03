import Foundation
import Testing
@testable import NSG

@MainActor
struct NikonBluetoothTests {
    @Test("Handshake messages use the protocol's little-endian byte order")
    func messageWireFormat() throws {
        let bytes = Data([
            2,
            0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01,
            0x44, 0x33, 0x22, 0x11,
            0x88, 0x77, 0x66, 0x55
        ])
        let message = try NikonPairingMessage(data: bytes)
        #expect(message.stage == 2)
        #expect(message.timestamp == 0x0102030405060708)
        #expect(message.device == 0x11223344)
        #expect(message.nonce == 0x55667788)
        #expect(message.data == bytes)
    }

    @Test("Reject truncated and oversized handshake messages", arguments: [0, 16, 18])
    func invalidMessageLength(count: Int) {
        #expect(throws: NikonPairingError.self) {
            _ = try NikonPairingMessage(data: Data(repeating: 0, count: count))
        }
    }

    @Test("Preserve controller identity after camera reconnection and peripheral UUID changes")
    func persistentIdentity() throws {
        let suite = "NSGTests.identity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NikonProbeIdentityStore(defaults: defaults)
        let identifier = UUID()
        let first = try store.resolve(identifier: identifier, name: "Z5", systemConnected: false)
        let reconnected = try store.resolve(identifier: identifier, name: "Z5", systemConnected: false)
        let changedUUID = try store.resolve(identifier: UUID(), name: "Z5", systemConnected: false)
        #expect(first.identity == reconnected.identity)
        #expect(first.identity == changedUUID.identity)
        #expect(first.identity.device & 0xFF == 1)
    }

    @Test("Reject arbitrary migration to a system peripheral when multiple legacy identities exist")
    func ambiguousLegacyIdentity() throws {
        let suite = "NSGTests.identity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for device: UInt32 in [1, 257] {
            let message = NikonPairingMessage(stage: 1, timestamp: 0, device: device, nonce: 42)
            defaults.set(message.data, forKey: "NikonProbe.identity.\(UUID().uuidString)")
        }
        let store = NikonProbeIdentityStore(defaults: defaults)
        #expect(throws: NikonProbeError.self) {
            _ = try store.resolve(identifier: UUID(), name: nil, systemConnected: true)
        }
    }
}
