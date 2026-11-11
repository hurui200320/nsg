import SwiftUI

struct SettingsView: View {
    let services: AppServiceController
    @State private var isTipsPresented = false

    var body: some View {
        Form {
            bluetoothSection
            locationSection
            otherSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .sheet(isPresented: $isTipsPresented) {
            TipsView()
                .presentationDragIndicator(.visible)
        }
    }

    private var bluetoothSection: some View {
        Section {
            Toggle("Scan nearby devices", isOn: Binding(
                get: { services.isNearbyScanningEnabled },
                set: { services.setNearbyScanningEnabled($0) }
            ))
            .accessibilityIdentifier("nearbyScanningToggle")
        } header: {
            Text("Bluetooth")
        }
    }

    private var locationSection: some View {
        Section {
            Toggle("Show map preview", isOn: Binding(
                get: { services.isMapPreviewEnabled },
                set: { services.setMapPreviewEnabled($0) }
            ))
            .accessibilityIdentifier("mapPreviewToggle")

            Picker("Send interval", selection: Binding(
                get: { services.locationSendInterval },
                set: { services.setLocationSendInterval($0) }
            )) {
                ForEach(LocationSendInterval.allCases, id: \.self) { interval in
                    Text(interval.title).tag(interval)
                }
            }
            .accessibilityIdentifier("locationSendIntervalPicker")

            Picker("Sending accuracy", selection: Binding(
                get: { services.locationAccuracy },
                set: { services.setLocationAccuracy($0) }
            )) {
                ForEach(LocationAccuracy.allCases, id: \.self) { accuracy in
                    Text("Within \(Int(accuracy.rawValue)) m").tag(accuracy)
                }
            }
            .accessibilityIdentifier("locationAccuracyPicker")
        } header: {
            Text("GPS")
        }
    }

    private var otherSection: some View {
        Section("Other") {
            Button {
                isTipsPresented = true
            } label: {
                HStack {
                    Text("Tips")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tipsButton")

            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
        }
    }
}

struct TipsView: View {
    // TODO: Add useful tips for NSG
    // Displayed in Settings -> Other -> Tips

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Placeholder now")
                .navigationTitle("Tips")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark", role: .close) {
                            dismiss()
                        }
                        .labelStyle(.iconOnly)
                    }
                }
        }
    }
}

#if DEBUG

#Preview {
    NavigationStack {
        SettingsView(services: AppServiceController())
    }
}

#endif
