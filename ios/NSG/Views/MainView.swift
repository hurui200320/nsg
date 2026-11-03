//
//  MainView.swift
//  NSG
//
//  Created by forLG on 2026/11/3.
//

import SwiftUI
import CoreBluetooth

struct MainView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bluetoothService = BluetoothService()
    
    var body: some View {
        List {
            otherDeviceSection
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.3),
            value: bluetoothService.devices.map(\.identifier)
        )
        .onAppear {
            bluetoothService.startScan()
        }
        .onDisappear {
            bluetoothService.stopScan()
        }
    }
    
    
    private var MyDeviceSection: some View {
        Section {
            // TODO: Display the Nikon cameras that are already connected before
        } header: {
            Text("My camera")
        }
    }

    private var otherDeviceSection: some View {
        Section {
            if bluetoothService.devices.isEmpty {
                
            } else {
                ForEach(bluetoothService.devices, id: \.identifier) { device in
                    Text(device.name ?? "Unknown camera")
                }
            }
        } header: {
            HStack {
                Text("Other camera")
                if bluetoothService.isScanning {
                    ProgressView()
                        .accessibilityLabel("Scanning for cameras")
                }
            }
        }
    }
    
    
    private var SettingSection: some View {
        Section {
            // TODO: Adjust settings like frequency of sending location, accuracy of location, etc.
        } header: {
            Text("Settings")
        }
    }
}

#if DEBUG
#Preview {
    MainView()
}
#endif
