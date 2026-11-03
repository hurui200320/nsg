//
//  Bluetooth+Scanning.swift
//  NSG
//

import Foundation
import CoreBluetooth

extension BluetoothService {
    // MARK: - Initialization and scanning

    /// Initialize the manager without automatically scanning. Bluetooth state updates asynchronously.
    func prepare() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// May be called before prepare; during initial setup, wait for poweredOn before proceeding.
    func startScan() {
        guard activePeripheral == nil, !isPairing, !scanRequested else { return }
        if let central, central.state != .poweredOn &&
            central.state != .unknown && central.state != .resetting {
            return
        }

        scanRequested = true
        devices.removeAll()
        prepare()
        beginScanIfReady()
    }

    func stopScan(cancelAutoReconnect: Bool = true) {
        if cancelAutoReconnect && (reconnectionTarget != nil || automaticReconnectTask != nil) {
            disableAutomaticReconnection()
        }
        cancelTargetReconnection()
        scanRequested = false
        if central?.isScanning == true {
            central?.stopScan()
        }
        isScanning = false
    }

    func beginScanIfReady() {
        guard scanRequested, canScan, let central,
              central.state == .poweredOn, !central.isScanning else { return }
        central.scanForPeripherals(
            withServices: [nikonService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        isScanning = central.isScanning
    }
}

// MARK: - Bluetooth state and scanning callbacks

extension BluetoothService: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        if central.state == .poweredOn {
            if !resumeAutomaticReconnection() {
                beginScanIfReady()
            }
            return
        }
        cancelAutomaticReconnectTask()
        isScanning = false
        devices.removeAll()
        // Target reconnection can wait for initial setup or a brief reset, subject to the same 30-second timeout.
        if reconnectionTarget != nil, activePeripheral == nil,
           !isPairingPickerPresented,
           central.state == .unknown || central.state == .resetting {
            return
        }
        // Initial unknown/resetting states can wait for setup; other states require an explicit scan retry.
        if central.state != .unknown && central.state != .resetting {
            scanRequested = false
        }
        let hadActiveFlow = activePeripheral != nil || isPairing
        cancelTargetReconnection()
        pairingTarget = nil
        connectingCameraID = nil
        clearHandshake()
        firstPairingRequested = false
        if let peripheral = activePeripheral {
            releasePeripheral(peripheral)
        }
        if hadActiveFlow {
            connectionState = .failed("Bluetooth is unavailable")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isScanning, central.state == .poweredOn else { return }
        if !devices.contains(where: { $0.identifier == peripheral.identifier }) {
            devices.append(peripheral)
        }
        reconnectIfMatched(peripheral, advertisementData: advertisementData)
    }
}
