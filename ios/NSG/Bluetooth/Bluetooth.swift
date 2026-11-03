//
//  Bluetooth.swift
//  NSG
//
//  Created by forLG on 2026/11/3.
//

import SwiftUI
import CoreBluetooth
import Observation

@MainActor
@Observable
final class BluetoothService: NSObject {
    private let nikonService = CBUUID(
        string: "0000DE00-3DD4-4255-8D62-6DC7B9BD5561"
    )

    private(set) var bluetoothState: CBManagerState = .unknown
    private(set) var devices: [CBPeripheral] = []
    private var peripherals: [UUID: CBPeripheral] = [:]
    
    private(set) var isScanning: Bool = false
    
    @ObservationIgnored
    private var central: CBCentralManager?
    
    // Start the bluetooth service
    func prepare() {
        guard central == nil else { return }
        
        central = CBCentralManager(
            delegate: self,
            queue: .main
        )
    }
 
    func startScan() {
        guard bluetoothState == .poweredOn,
                let central,
              !central.isScanning else {
            return
        }
        
        devices.removeAll()
        peripherals.removeAll()

        central.scanForPeripherals(
            withServices: [nikonService],
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ]
        )
    }

    func stopScan() {
        central?.stopScan()
        isScanning = false
    }
}

extension BluetoothService: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state

        if central.state != .poweredOn {
            isScanning = false
            devices.removeAll()
            peripherals.removeAll()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isScanning, central.state == .poweredOn else { return }

        let identifier = peripheral.identifier
        if peripherals[identifier] == nil {
            devices.append(peripheral)
        }
        peripherals[identifier] = peripheral
    }
}
