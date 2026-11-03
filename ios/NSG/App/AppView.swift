//
//  AppView.swift
//  NSG
//
//  Created by forLG on 2026/11/3.
//

import SwiftUI
import CoreBluetooth
import UIKit

struct AppView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var bluetoothService = BluetoothService()
    @State private var isLaunched = false
    @State private var launchRequested = false

    var body: some View {
        NavigationStack {
            Group {
                if isLaunched {
                    MainView(bluetoothService: bluetoothService)
                } else {
                    VStack() {
                        if launchRequested {
                            if bluetoothService.bluetoothState == .unknown ||
                                bluetoothService.bluetoothState == .resetting {
                                ProgressView()
                            }
                            Text(launchMessage)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            if bluetoothService.bluetoothState == .unauthorized {
                                Button("Open Settings") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        openURL(url)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(reduceMotion ? nil: .smooth(duration: 0.3), value: isLaunched)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("Nikon Smart GPS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if launchRequested || isLaunched {
                            launchRequested = false
                            isLaunched = false
                            bluetoothService.stopLocationSync()
                            bluetoothService.disconnect()
                        } else {
                            launchRequested = true
                            bluetoothService.prepare()
                            openCamerasIfReady()
                        }
                    } label: {
                        Label(launchRequested || isLaunched ? "Stop Bluetooth" : "Start Bluetooth", systemImage: "power")
                    }
                    .tint(launchRequested || isLaunched ? .blue : .primary)
                    .labelStyle(.iconOnly)
                    .disabled(bluetoothService.isPairingPickerPresented)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // TODO: Add a setting button to adjust sending frequncey, etc.
                    } label: {
                        Label("Setting", systemImage: "gearshape")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(true)
                }
            }
        }
        .onChange(of: bluetoothService.bluetoothState) { _, _ in
            openCamerasIfReady()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, isLaunched {
                bluetoothService.resumeAutomaticReconnection()
            }
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
            }
        }
    }

    private func openCamerasIfReady() {
        guard launchRequested, bluetoothService.bluetoothState == .poweredOn else { return }
        launchRequested = false
        isLaunched = true
    }

    private var launchMessage: String {
        switch bluetoothService.bluetoothState {
        case .unknown: return "Preparing Bluetooth…"
        case .resetting: return "Bluetooth is restarting…"
        case .poweredOff: return "Turn on Bluetooth in Settings or Control Center. Your cameras will open when Bluetooth is ready."
        case .unauthorized: return "Allow Bluetooth access in Settings to connect to your camera."
        case .unsupported: return "Bluetooth is unavailable on this device."
        case .poweredOn: return "Opening cameras…"
        @unknown default: return "Bluetooth is unavailable."
        }
    }
}

#if DEBUG
#Preview {
    AppView()
}
#endif
