import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let services: AppServiceController

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Scan nearby devices", isOn: Binding(
                        get: { services.isNearbyScanningEnabled },
                        set: { services.setNearbyScanningEnabled($0) }
                    ))
                    .accessibilityIdentifier("nearbyScanningToggle")
                } footer: {
                    Text("Discover nearby cameras while the camera list is open. Saved cameras can still reconnect when scanning is off.")
                }

                Section {
                    Picker("Send interval", selection: Binding(
                        get: { services.locationSendInterval },
                        set: { services.setLocationSendInterval($0) }
                    )) {
                        ForEach(LocationSendInterval.allCases, id: \.self) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }
                    .accessibilityIdentifier("locationSendIntervalPicker")
                } footer: {
                    Text("Minimum time between automatic sends. Sending waits for a fresh location that meets the accuracy requirement.")
                }

                Section {
                    Picker("Sending accuracy", selection: Binding(
                        get: { services.locationAccuracy },
                        set: { services.setLocationAccuracy($0) }
                    )) {
                        ForEach(LocationAccuracy.allCases, id: \.self) { accuracy in
                            Text("Within \(Int(accuracy.rawValue)) m").tag(accuracy)
                        }
                    }
                    .accessibilityIdentifier("locationAccuracyPicker")
                } footer: {
                    Text("Only send locations whose reported horizontal error is within this range. Smaller values may take longer. Actual accuracy depends on GPS conditions and Precise Location permission.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
