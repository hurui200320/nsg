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
        let store = NikonIdentityStore(defaults: defaults)
        let identifier = UUID()
        let first = store.resolve(identifier: identifier)
        let reconnected = store.resolve(identifier: identifier)
        let changedIdentifier = UUID()
        store.associate(first, identifier: changedIdentifier)
        let changedUUID = store.resolve(identifier: changedIdentifier)
        #expect(first == reconnected)
        #expect(first == changedUUID)
        #expect(first.device & 0xFF == 1)
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
        let store = NikonIdentityStore(defaults: defaults)
        #expect(throws: NikonIdentityError.self) {
            _ = try store.migrateLegacyIdentity(to: UUID())
        }
    }
    @Test("New cameras with the same name receive independent controller identities")
    func sameNameDoesNotShareIdentity() throws {
        let suite = "NSGTests.identity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = NikonPairingMessage(stage: 1, timestamp: 0, device: 1, nonce: 42)
        defaults.set(legacy.data, forKey: "NikonProbe.cameraIdentity.Z5")
        let repository = CameraRepository(defaults: defaults)
        let first = repository.identity(for: CameraDevice(id: UUID(), name: "Z5"),
                                        camera: nil, knownCameras: [])
        let second = repository.identity(for: CameraDevice(id: UUID(), name: "Z5"),
                                         camera: nil, knownCameras: [])
        #expect(first != second)
        #expect(first.stage1Identity != legacy)
        #expect(second.stage1Identity != legacy)
    }
    // Shared captured Z50 II vector from Android's NikonPairingEngineTest.
    @Test("Captured Stage 2 produces the exact Stage 3 wire bytes")
    func capturedChallenge() throws {
        let stage1 = NikonPairingMessage(stage: 1, timestamp: 0x677DA144EC13E1DB,
                                        device: 0x3C3AE501, nonce: 0x3FDAA451)
        let stage2 = NikonPairingMessage(stage: 2, timestamp: 0xB9943D5E8026FA29,
                                        device: 0xA8B3F2E4, nonce: 0x16D56A13)
        let response = try NikonPairingProtocol.response(to: stage2, stage1: stage1)
        #expect(response.data == Data([
            3, 0xDB, 0xE1, 0x13, 0xEC, 0x44, 0xA1, 0x7D, 0x67,
            0x53, 0xAD, 0xF1, 0x79, 0x35, 0x8A, 0x83, 0x23
        ]))
    }

    @Test("Invalid camera challenges are rejected")
    func rejectedChallenge() {
        #expect(throws: NikonPairingError.self) {
            _ = try NikonPairingProtocol.response(
                to: NikonPairingMessage(stage: 2, timestamp: 0, device: 0, nonce: 0),
                stage1: NikonPairingMessage(stage: 1, timestamp: 1, device: 1, nonce: 42)
            )
        }
    }
}
