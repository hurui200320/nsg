import Foundation
import CoreBluetooth

/// Executes Bluetooth commands and converts system callbacks into events; owns peripherals, characteristics,
/// and the write queue.
@MainActor
final class BluetoothTransport: NSObject, CameraTransport {
    var onEvent: ((CameraTransportEvent) -> Void)?

    private var central: CBCentralManager?
    /// Caches discovered peripheral objects; connect looks up the object using the device ID supplied by the
    /// UI.
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var activePeripheral: CBPeripheral?
    private var sessionID: UUID?
    private var characteristics: [NikonCharacteristic: CBCharacteristic] = [:]
    /// Pending scan intent, retained through initialization or reset until poweredOn allows scanning.
    private var scanMode: CameraScanMode?
    private var isForeground = true
    private var writeQueue = CameraWriteQueue()
    private var isDisconnecting = false

    /// Creates the manager when Bluetooth is first enabled; safe to repeat, with state changes reported through
    /// onEvent.
    func prepare() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// Updates scan filtering on foreground/background changes; restarts an existing scan with the new policy.
    func setForeground(_ isForeground: Bool) {
        guard self.isForeground != isForeground else { return }
        self.isForeground = isForeground
        if scanMode != nil {
            central?.stopScan()
            beginScanIfReady()
        }
    }

    /// Records a requested scan mode; scanning begins once the manager is ready.
    func startScan(mode: CameraScanMode) {
        scanMode = mode
        prepare()
        central?.stopScan()
        beginScanIfReady()
    }

    func stopScan() {
        scanMode = nil
        central?.stopScan()
        onEvent?(.scanningChanged(false))
    }

    private func beginScanIfReady() {
        guard let central, central.state == .poweredOn, let scanMode,
              activePeripheral?.state != .connecting, !central.isScanning else { return }
        central.scanForPeripherals(
            withServices: NikonScanPolicy.services(for: scanMode, isForeground: isForeground),
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        onEvent?(.scanningChanged(central.isScanning))
    }

    /// Binds the requested session and peripheral; the device must already be cached from discovery, otherwise
    /// termination is reported.
    func connect(_ device: CameraDevice, sessionID: UUID) {
        guard let central, central.state == .poweredOn, activePeripheral == nil,
              let peripheral = peripherals[device.id] else {
            onEvent?(.disconnected(sessionID, CameraFailure("Camera is no longer available. Scan again.")))
            return
        }
        self.sessionID = sessionID
        isDisconnecting = false
        activePeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    /// Discards queued writes and requests disconnection; retains the peripheral until the final callback.
    func disconnect(sessionID: UUID) {
        guard sessionID == self.sessionID, let activePeripheral else { return }
        isDisconnecting = true
        writeQueue.removeAll()
        central?.cancelPeripheralConnection(activePeripheral)
    }

    func subscribe(_ characteristic: NikonCharacteristic, sessionID: UUID) {
        guard sessionID == self.sessionID, !isDisconnecting, let peripheral = activePeripheral,
              let value = characteristics[characteristic] else { return }
        if value.isNotifying {
            onEvent?(.subscriptionChanged(sessionID, characteristic, true, nil))
        } else {
            peripheral.setNotifyValue(true, for: value)
        }
    }

    func read(_ characteristic: NikonCharacteristic, sessionID: UUID) {
        guard sessionID == self.sessionID, let peripheral = activePeripheral,
              let value = characteristics[characteristic], value.properties.contains(.read) else { return }
        peripheral.readValue(for: value)
    }

    /// Enqueues handshake or GEO data; returning does not indicate success, which requires a writeCompleted
    /// event.
    func write(_ data: Data, to characteristic: NikonCharacteristic, sessionID: UUID) {
        guard sessionID == self.sessionID, !isDisconnecting else { return }
        writeQueue.enqueue(data, to: characteristic)
        drainWrites()
    }

    /// Called after enqueue or acknowledgement; submits at most one write awaiting ATT acknowledgement at a
    /// time.
    private func drainWrites() {
        guard !isDisconnecting, let peripheral = activePeripheral,
              peripheral.state == .connected, let sessionID, let request = writeQueue.next() else { return }
        let kind = request.characteristic
        let data = request.data
        guard let characteristic = characteristics[kind], characteristic.properties.contains(.write),
              data.count <= peripheral.maximumWriteValueLength(for: .withResponse) else {
            onEvent?(.failed(sessionID, CameraFailure("Characteristic is not writable or data exceeds its length limit.",
                                                    recovery: .userAction)))
            return
        }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    /// Clears peripheral, characteristics, and queue after termination or Bluetooth unavailability; does not
    /// request disconnection.
    private func releaseConnection() {
        activePeripheral?.delegate = nil
        activePeripheral = nil
        sessionID = nil
        isDisconnecting = false
        characteristics.removeAll()
        writeQueue.removeAll()
    }

    /// Validates callback objects against the current connection; only termination callbacks may allow a
    /// disconnecting session.
    private func currentSession(_ peripheral: CBPeripheral, characteristic: CBCharacteristic? = nil,
                                allowDisconnecting: Bool = false) -> UUID? {
        guard peripheral === activePeripheral, let sessionID,
              allowDisconnecting || !isDisconnecting else { return nil }
        if let characteristic {
            guard let kind = NikonCharacteristic(uuid: characteristic.uuid),
                  characteristics[kind] === characteristic else { return nil }
        }
        return sessionID
    }
}

extension BluetoothTransport: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            onEvent?(.scanningChanged(false))
            // CoreBluetooth invalidates peripheral objects when the manager resets.
            releaseConnection()
            peripherals.removeAll()
        }
        onEvent?(.stateChanged(central.state))
        if central.state == .poweredOn { beginScanIfReady() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanMode != nil, central.isScanning, central.state == .poweredOn else { return }
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard NikonScanPolicy.isNikonAdvertisement(services: services, manufacturerData: manufacturer) else { return }
        peripherals[peripheral.identifier] = peripheral
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        onEvent?(.discovered(CameraDevice(id: peripheral.identifier, name: name), manufacturer))
    }

    /// Starts service discovery after BLE connection succeeds; the Nikon handshake has not completed yet.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let sessionID = currentSession(peripheral) else { return }
        onEvent?(.discovering(sessionID))
        peripheral.discoverServices([NikonCharacteristic.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finishDisconnection(peripheral, error: error)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        finishDisconnection(peripheral, error: error)
    }

    private func finishDisconnection(_ peripheral: CBPeripheral, error: Error?) {
        guard let sessionID = currentSession(peripheral, allowDisconnecting: true) else { return }
        releaseConnection()
        onEvent?(.disconnected(sessionID, error.map { CameraFailure(error: $0) }))
    }
}

extension BluetoothTransport: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let sessionID = currentSession(peripheral) else { return }
        if let error {
            onEvent?(.failed(sessionID, CameraFailure(error: error)))
        } else if let service = peripheral.services?.first(where: { $0.uuid == NikonCharacteristic.serviceUUID }) {
            peripheral.discoverCharacteristics(NikonCharacteristic.allCases.map(\.uuid), for: service)
        } else {
            onEvent?(.failed(sessionID, CameraFailure("Nikon service not found.", recovery: .userAction)))
        }
    }

    /// Reports connected and a capability snapshot after characteristic discovery; the camera service decides
    /// whether to start the handshake.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let sessionID = currentSession(peripheral), service.uuid == NikonCharacteristic.serviceUUID else { return }
        if let error {
            onEvent?(.failed(sessionID, CameraFailure(error: error)))
            return
        }
        for characteristic in service.characteristics ?? [] {
            if let kind = NikonCharacteristic(uuid: characteristic.uuid) { characteristics[kind] = characteristic }
        }
        onEvent?(.connected(sessionID, NikonCameraCapabilities(
            properties: characteristics.mapValues(\.properties),
            maximumWriteLength: peripheral.maximumWriteValueLength(for: .withResponse)
        )))
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard let sessionID = currentSession(peripheral),
              invalidatedServices.contains(where: { $0.uuid == NikonCharacteristic.serviceUUID }) else { return }
        onEvent?(.failed(sessionID, CameraFailure("Camera services changed. Reconnecting.")))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let sessionID = currentSession(peripheral, characteristic: characteristic),
              let kind = NikonCharacteristic(uuid: characteristic.uuid) else { return }
        onEvent?(.subscriptionChanged(sessionID, kind, characteristic.isNotifying,
                                     error.map { CameraFailure(error: $0) }))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let sessionID = currentSession(peripheral, characteristic: characteristic),
              let kind = NikonCharacteristic(uuid: characteristic.uuid) else { return }
        if let error {
            onEvent?(.failed(sessionID, CameraFailure(error: error)))
        } else if let data = characteristic.value {
            onEvent?(.valueReceived(sessionID, kind, data))
        }
    }

    /// Reports the acknowledged write, then advances the queue; ignores callbacks that mismatch or arrive
    /// during disconnection.
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let sessionID = currentSession(peripheral, characteristic: characteristic),
              let kind = NikonCharacteristic(uuid: characteristic.uuid), writeQueue.acknowledge(kind) else { return }
        onEvent?(.writeCompleted(sessionID, kind, error.map { CameraFailure(error: $0) }))
        drainWrites()
    }
}
