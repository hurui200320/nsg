//
//  Bluetooth+Connection.swift
//  NSG
//

import Foundation
import CoreBluetooth

extension BluetoothService {
    // MARK: - Connection

    /// Pass true for initial pairing: release GATT after the handshake and automatically open the system pairing dialog.
    /// Pass false for normal connections: reuse the controller identity, retain GATT after the handshake, and enter ready.
    /// For initial pairing, the camera must be in “Connect to smart device → Start pairing” mode.
    func connect(_ peripheral: CBPeripheral, firstPairing: Bool = false, isAutomatic: Bool = false) {
        guard let central, central.state == .poweredOn,
              activePeripheral == nil, !isPairing else { return }
        if !isAutomatic {
            if let camera = knownCameras.first(where: { $0.peripheralIdentifier == peripheral.identifier }),
               !firstPairing {
                enableAutomaticReconnection(for: camera.id)
            } else {
                // When the user selects a new camera, do not silently reconnect to the previous camera after a failure.
                disableAutomaticReconnection()
            }
        }
        stopScan(cancelAutoReconnect: false)
        clearHandshake()
        characteristics.removeAll()
        pairingTarget = nil
        connectingCameraID = knownCameras.first { $0.peripheralIdentifier == peripheral.identifier }?.id
        firstPairingRequested = firstPairing
        activePeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        armTimeout("Connecting to camera")
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        // The user must complete or cancel the system dialog; cancelling the Task cannot dismiss it.
        guard !isPairingPickerPresented else { return }
        disableAutomaticReconnection()
        stopScan(cancelAutoReconnect: false)
        pairingTarget = nil
        connectingCameraID = nil
        firstPairingRequested = false
        clearHandshake()
        guard let peripheral = activePeripheral else {
            connectionState = .disconnected
            return
        }
        connectionState = .disconnecting
        // Wait for the disconnection callback before releasing the peripheral to avoid overlapping old and new connections.
        central?.cancelPeripheralConnection(peripheral)
    }

    func releasePeripheral(_ peripheral: CBPeripheral) {
        peripheral.delegate = nil
        activePeripheral = nil
        connectingCameraID = nil
        characteristics.removeAll()
    }
}

// MARK: - Connection callbacks

extension BluetoothService {
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === activePeripheral, connectionState == .connecting else { return }
        connectionState = .discovering
        armTimeout("Discovering services and characteristics")
        peripheral.discoverServices([nikonService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard peripheral === activePeripheral else { return }
        clearHandshake()
        firstPairingRequested = false
        releasePeripheral(peripheral)
        if case .failed = connectionState {
            scheduleAutomaticReconnection()
            return
        }
        if connectionState == .disconnecting {
            connectionState = .disconnected
        } else {
            connectionState = .failed(error.map { describe($0) } ?? "Connection failed")
            scheduleAutomaticReconnection()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard peripheral === activePeripheral else { return }
        let shouldShowPicker = connectionState == .disconnectingForPairing
        let wasDisconnecting = connectionState == .disconnecting
        clearHandshake()
        releasePeripheral(peripheral)
        if shouldShowPicker {
            showPairingPicker()
            return
        }
        firstPairingRequested = false
        if case .failed = connectionState {
            scheduleAutomaticReconnection()
            return
        }
        if !wasDisconnecting, let error {
            connectionState = .failed(describe(error))
        } else {
            connectionState = .disconnected
        }
        if !wasDisconnecting {
            scheduleAutomaticReconnection()
        }
    }
}

// MARK: - Service and characteristic discovery

extension BluetoothService: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === activePeripheral, connectionState == .discovering else { return }
        if let error {
            fail(describe(error))
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == nikonService }) else {
            fail("Nikon service not found")
            return
        }
        peripheral.discoverCharacteristics([pairUUID, not1UUID, idUUID, geoUUID], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard peripheral === activePeripheral, connectionState == .discovering,
              service.uuid == nikonService else { return }
        if let error {
            fail(describe(error))
            return
        }
        for characteristic in service.characteristics ?? [] {
            characteristics[characteristic.uuid] = characteristic
        }
        do {
            try startHandshake()
        } catch {
            fail(describe(error))
        }
    }
}
