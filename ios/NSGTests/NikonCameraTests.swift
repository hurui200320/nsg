import Foundation
import CoreBluetooth
import Testing
@testable import NSG

@MainActor
struct NikonCameraTests {
    private func camera(device: UInt32 = 0x11223301) -> NikonCameraRecord {
        let id = UUID()
        return NikonCameraRecord(
            id: id,
            peripheralIdentifier: id,
            name: "Z5",
            controllerDevice: device,
            controllerNonce: 42,
            pairingCompletedAt: Date(timeIntervalSince1970: 100),
            lastConnectedAt: nil
        )
    }

    @Test("Visible discovery pauses only during connecting and continues after connection")
    func visibleDiscovery() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        context.service.setDiscoveryVisible(true)
        context.transport.emit(.stateChanged(.poweredOn))
        #expect(context.service.isScanning)

        let device = CameraDevice(id: UUID(), name: "Z5")
        context.transport.emit(.discovered(device, nil))
        context.service.connect(device)
        let session = try #require(context.transport.connections.last?.1)
        #expect(context.service.connectionState == .connecting)
        #expect(!context.service.isScanning)

        context.transport.emit(.discovering(session))
        #expect(context.service.isScanning)
        #expect(context.service.devices.contains(where: { $0.id == device.id }))
        context.transport.emit(.connected(session, CameraCapabilities(properties: [
            .pairing: [.write, .indicate, .read], .success: [.notify],
            .controllerName: [.write], .location: [.write]
        ], maximumWriteLength: 512)))
        context.transport.emit(.subscriptionChanged(session, .pairing, true, nil))
        context.transport.emit(.subscriptionChanged(session, .success, true, nil))
        context.finishHandshake(session)
        #expect(context.service.connectionState == .ready)
        #expect(context.service.isScanning)

        let other = CameraDevice(id: UUID(), name: "Z6")
        context.transport.emit(.discovered(other, nil))
        #expect(context.service.devices.contains(where: { $0.id == other.id }))
        context.service.setDiscoveryVisible(false)
        #expect(!context.service.isScanning)
        #expect(context.service.connectionState == .ready)
    }

    @Test("Persist known cameras and restore them when the service initializes")
    func persistence() throws {
        let suite = "NSGTests.cameras.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let target = camera()
        let store = NikonCameraStore(defaults: defaults)
        try store.save([target])
        #expect(store.load() == [target])
        let service = NikonCameraService(defaults: defaults, transport: FakeCameraTransport())
        #expect(service.knownCameras == [target])
        service.forgetCamera(target)
        #expect(store.load().isEmpty)
    }

    @Test("Match Nikon advertisements after UUID changes and reject incorrect manufacturers and identities")
    func advertisementMatching() {
        let target = camera()
        let data = Data([0x99, 0x03, 0x01, 0x33, 0x22, 0x11, 0x1E])
        #expect(NikonCameraMatcher.matches(
            target, identifier: UUID(), manufacturerData: data, knownCameras: [target]
        ))
        #expect(!NikonCameraMatcher.matches(
            target, identifier: UUID(),
            manufacturerData: Data([0x98, 0x03, 0x01, 0x33, 0x22, 0x11, 0]),
            knownCameras: [target]
        ))
        #expect(!NikonCameraMatcher.matches(
            target, identifier: UUID(),
            manufacturerData: Data([0x99, 0x03, 0x02, 0x33, 0x22, 0x11, 0]),
            knownCameras: [target]
        ))
        #expect(!NikonCameraMatcher.matches(
            target, identifier: UUID(), manufacturerData: nil, knownCameras: [target]
        ))
        #expect(NikonCameraMatcher.matches(
            target, identifier: target.peripheralIdentifier,
            manufacturerData: nil, knownCameras: [target]
        ))
    }

    @Test("Reject automatic matching when controller advertisement identifiers conflict")
    func ambiguousAdvertisement() {
        let target = camera()
        let other = camera()
        #expect(!NikonCameraMatcher.matches(
            target, identifier: UUID(),
            manufacturerData: Data([0x99, 0x03, 0x01, 0x33, 0x22, 0x11, 0]),
            knownCameras: [target, other]
        ))
    }

    @Test("Associate the original handshake identity after UUID changes without creating a new identity")
    func identityAssociation() throws {
        let suite = "NSGTests.cameras.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let target = camera()
        let identifier = UUID()
        let store = NikonIdentityStore(defaults: defaults)
        store.associate(target.identity, identifier: identifier)
        let resolved = store.resolve(identifier: identifier)
        #expect(resolved == target.identity)
    }

    @Test("Stopping target scanning preserves saved camera records")
    func cancelReconnection() throws {
        let target = camera()
        let context = try CameraTestContext(cameras: [target])
        defer { context.cleanup() }
        context.transport.emit(.stateChanged(.poweredOn))
        context.service.connectKnownCamera(target)
        context.service.stopScan()
        #expect(context.service.connectionState == .disconnected)
        #expect(!context.service.isScanning)
        #expect(context.service.knownCameras == [target])
    }

    @Test("Saved records restore the original identity when a transport UUID alias is missing")
    func savedRecordIdentity() throws {
        let suite = "NSGTests.cameras.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let target = camera()
        let device = CameraDevice(id: UUID(), name: target.name)
        let restored = CameraRepository(defaults: defaults).identity(
            for: device, camera: target, knownCameras: [target]
        )
        #expect(restored == target.identity)
        #expect(NikonIdentityStore(defaults: defaults).identity(for: device.id) == target.identity)
    }

    @Test("Preserve stable record IDs when updating peripheral UUIDs and last-used timestamps")
    func connectionMetadata() throws {
        let suite = "NSGTests.cameras.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = camera()
        var updated = original
        updated.peripheralIdentifier = UUID()
        updated.lastConnectedAt = Date(timeIntervalSince1970: 200)
        let store = NikonCameraStore(defaults: defaults)
        try store.save([updated])
        let loaded = try #require(store.load().first)
        #expect(loaded.id == original.id)
        #expect(loaded.peripheralIdentifier != original.peripheralIdentifier)
        #expect(loaded.lastConnectedAt == updated.lastConnectedAt)
    }
}
