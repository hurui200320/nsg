import CoreBluetooth
import Testing
@testable import NSG

@MainActor
struct AppServiceControllerTests {
    @Test("Enabling GPS acquires without Bluetooth; only a completed handshake permits sending")
    func independentLocationAcquisition() throws {
        let context = try CameraTestContext(bluetoothEnabled: false, locationEnabled: false)
        defer { context.cleanup() }
        context.services.setLocationEnabled(true)
        #expect(context.location.isRunning)
        #expect(!context.services.isBluetoothEnabled)
        #expect(context.transport.prepareCount == 0)
        context.location.emit(context.fix())
        context.service.sendCurrentLocation()
        #expect(context.transport.writes.isEmpty)

        context.services.setBluetoothEnabled(true)
        let session = try context.connect()
        #expect(context.transport.writes.filter { $0.0 == .location }.isEmpty)
        context.finishHandshake(session)
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 1)
    }

    @Test("Bluetooth shutdown cancels discovery and retries; late events cannot resume them")
    func bluetoothShutdownDuringDiscovery() throws {
        let target = CameraTestContext.camera(connectedAt: .now)
        let context = try CameraTestContext(cameras: [target])
        defer { context.cleanup() }
        context.transport.emit(.stateChanged(.poweredOn))
        #expect(context.service.isScanning)
        let scans = context.transport.scans.count
        context.services.setBluetoothEnabled(false)
        #expect(!context.service.isScanning)
        #expect(!context.service.isAutomaticReconnectEnabled)
        #expect(!NikonAutoReconnectStore(defaults: context.defaults).load(knownCameras: [target]).isEnabled)
        #expect(context.location.isRunning)

        context.transport.emit(.scanningChanged(true))
        context.transport.emit(.discovered(CameraDevice(id: target.peripheralIdentifier, name: target.name), nil))
        context.transport.emit(.stateChanged(.poweredOff))
        context.transport.emit(.stateChanged(.poweredOn))
        context.service.setDiscoveryVisible(true)
        context.service.startScan()
        context.service.prepare()
        context.service.connectKnownCamera(target)
        context.service.resumeAutomaticReconnection()
        context.scheduler.advance(by: 120)
        #expect(!context.service.isScanning)
        #expect(context.transport.scans.count == scans)
        #expect(context.transport.prepareCount == 0)
        #expect(context.transport.connections.isEmpty)

        context.services.setBluetoothEnabled(true)
        #expect(context.transport.prepareCount == 1)
        #expect(context.service.isScanning)
    }

    @Test("Bluetooth shutdown disconnects the camera without stopping app GPS")
    func bluetoothShutdownDuringConnection() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        let session = try context.connect()
        context.finishHandshake(session)
        context.services.setBluetoothEnabled(false)
        #expect(context.transport.disconnections == [session])
        #expect(!context.service.canSendLocation)
        #expect(context.location.isRunning)
        let writes = context.transport.writes.count
        context.location.emit(context.fix())
        context.service.sendCurrentLocation()
        #expect(context.transport.writes.count == writes)
        context.transport.emit(.disconnected(session, nil))
        context.scheduler.advance(by: 120)
        #expect(context.service.connectionState == .disconnected)
        #expect(context.transport.scans.isEmpty)
    }

    @Test("GPS shutdown blocks all sends and remains off across camera reconnection")
    func locationShutdownSurvivesReconnection() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        let first = try context.connect()
        context.finishHandshake(first)
        context.services.setLocationEnabled(false)
        #expect(!context.location.isRunning)
        #expect(context.service.connectionState == .ready)
        #expect(!context.service.canSendLocation)
        #expect(!context.service.locationSync.send(context.fix()))
        context.service.sendCurrentLocation()
        #expect(context.transport.writes.filter { $0.0 == .location }.isEmpty)

        context.service.disconnect()
        context.transport.emit(.disconnected(first, nil))
        let second = try context.connect()
        context.finishHandshake(second)
        #expect(!context.services.isLocationEnabled)
        #expect(!context.location.isRunning)
        #expect(context.transport.writes.filter { $0.0 == .location }.isEmpty)

        context.services.setLocationEnabled(true)
        context.location.emit(context.fix())
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 1)
    }

    @Test("Camera disconnection preserves GPS intent and acquisition; reacquisition is unnecessary")
    func cameraDisconnectionPreservesLocation() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        let first = try context.connect()
        context.finishHandshake(first)
        context.transport.emit(.disconnected(first, nil))
        #expect(context.services.isLocationEnabled)
        #expect(context.location.isRunning)
        #expect(!context.service.canSendLocation)
        context.location.emit(context.fix())
        #expect(context.transport.writes.filter { $0.0 == .location }.isEmpty)

        let second = try context.connect()
        context.finishHandshake(second)
        #expect(context.location.isRunning)
        #expect(context.transport.writes.filter { $0.0 == .location }.count == 1)
    }

    @Test("Bluetooth cannot be disabled while the system pairing picker is open")
    func pairingPickerRetainsBluetoothIntent() async throws {
        var finishPicker: (@MainActor () -> Void)?
        let context = try CameraTestContext(picker: {
            await withCheckedContinuation { continuation in
                finishPicker = { continuation.resume(returning: .cancelled) }
            }
        })
        defer { context.cleanup() }
        let session = try context.connect(firstPairing: true)
        context.finishHandshake(session)
        context.transport.emit(.disconnected(session, nil))
        for _ in 0..<100 where finishPicker == nil { await Task.yield() }
        let finish = try #require(finishPicker)
        context.services.setBluetoothEnabled(false)
        #expect(context.services.isBluetoothEnabled)
        #expect(context.service.isPairingPickerPresented)
        finish()
        for _ in 0..<100 where context.service.isPairingPickerPresented { await Task.yield() }
        #expect(!context.service.isPairingPickerPresented)
        context.services.setBluetoothEnabled(false)
        #expect(!context.services.isBluetoothEnabled)
    }
}
