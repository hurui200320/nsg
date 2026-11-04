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
    @State private var services = AppServiceController()
    @State private var isLaunched = false
    @State private var isSettingsPresented = false
    private var bluetoothService: NikonCameraService { services.cameraService }

    var body: some View {
        NavigationStack {
            Group {
                if isLaunched {
                    MainView(
                        bluetoothService: bluetoothService,
                        isBluetoothEnabled: services.isBluetoothEnabled
                    )
                } else {
                    VStack() {
                        if services.isBluetoothEnabled {
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
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView(services: services)
            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Settings", systemImage: "gearshape") {
                        isSettingsPresented = true
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("settingsButton")
                }

                ToolbarSpacer(placement: .bottomBar)

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if services.isBluetoothEnabled {
                            isLaunched = true
                            services.setBluetoothEnabled(false)
                        } else {
                            services.setBluetoothEnabled(true)
                            openCamerasIfReady()
                        }
                    } label: {
                        Path { path in
                            path.move(to: CGPoint(x: 6, y: 0))
                            path.addLine(to: CGPoint(x: 6, y: 24))
                            path.addLine(to: CGPoint(x: 14, y: 17))
                            path.addLine(to: CGPoint(x: 0, y: 5))
                            path.move(to: CGPoint(x: 6, y: 0))
                            path.addLine(to: CGPoint(x: 14, y: 7))
                            path.addLine(to: CGPoint(x: 0, y: 19))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 14, height: 24)
                    }
                    .accessibilityLabel(services.isBluetoothEnabled ? "Stop Bluetooth" : "Start Bluetooth")
                    .tint(services.isBluetoothEnabled ? .blue : .primary)
                    .labelStyle(.iconOnly)
                    .disabled(bluetoothService.isPairingPickerPresented)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        services.setLocationEnabled(!services.isLocationEnabled)
                    } label: {
                        Label(services.isLocationEnabled ? "Stop GPS" : "Start GPS", systemImage: "location")
                    }
                    .labelStyle(.iconOnly)
                    .tint(services.isLocationEnabled ? .blue : .primary)
                }
            }
        }
        .task {
            services.startEnabledServices()
        }
        .onChange(of: bluetoothService.bluetoothState) { _, _ in
            openCamerasIfReady()
        }
        .onChange(of: scenePhase) { _, phase in
            bluetoothService.setForeground(phase == .active)
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
        guard services.isBluetoothEnabled, bluetoothService.bluetoothState == .poweredOn else { return }
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
