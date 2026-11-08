import SwiftUI
import CoreLocation

/// Presents the phone's GPS fix, map preview, and camera sharing status.
struct GPSLocationCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isMapPresented = false

    let location: CLLocation?
    let status: LocationStatus
    let lastSentAt: Date?
    let transferState: LocationTransferState
    let isLocationRunning: Bool
    let canSendLocation: Bool
    let sendLocation: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            mapPreview

            VStack(alignment: .leading, spacing: 16) {
                Label(statusTitle, systemImage: statusSymbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(statusColor)
                    .contentTransition(reduceMotion ? .identity : .opacity)
                
                Divider()

                if let location {
                    locationDetails(location)
                        .transition(.opacity)
                    
                    Divider()
                }

                transferStatus

                if isLocationRunning {
                    Button {
                        sendLocation()
                    } label: {
                        Label("Send now", systemImage: "paperplane")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSendLocation || transferState == .sending)
                    .transition(.opacity)
                }
            }
            .padding()
            .animation(informationAnimation, value: location != nil)
            .animation(informationAnimation, value: status)
            .animation(informationAnimation, value: transferState)
            .animation(informationAnimation, value: isLocationRunning)
            .animation(informationAnimation, value: canSendLocation)
            .animation(informationAnimation, value: lastSentAt)
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .sheet(isPresented: $isMapPresented) {
            GPSMapPage(location: location)
        }
    }

    private var informationAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.3)
    }

    private var mapPreview: some View {
        GPSMapView(location: location)
            .overlay(alignment: .topTrailing) {
                Button {
                    isMapPresented = true
                } label: {
                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .font(.caption.weight(.medium))
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .frame(width: 36, height: 36)
                .background(.regularMaterial, in: Circle())
                .foregroundStyle(.primary)
                .padding(12)
                .accessibilityLabel("Expand location map")
            }
            .frame(height: 200)
            .clipped()
    }

    private func locationDetails(_ location: CLLocation) -> some View {
        // Keep full coordinate values readable at larger accessibility sizes.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))

        return VStack(alignment: .leading, spacing: 16) {
            layout {
                metric("Latitude", value: coordinate(location.coordinate.latitude, positive: "N", negative: "S"))
                metric("Longitude", value: coordinate(location.coordinate.longitude, positive: "E", negative: "W"))
            }

            layout {
                metric("Accuracy", value: accuracy(location), isSecondary: true)
                metric("Altitude", value: altitude(location), isSecondary: true)
            }
        }
    }

    private func metric(_ title: String, value: String, isSecondary: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(isSecondary ? .subheadline : .headline)
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(informationAnimation, value: value)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var transferStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Last sent") {
                if let lastSentAt {
                    Text(lastSentAt, style: .time)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .transition(.opacity)
                } else {
                    Text("Not yet")
                        .transition(.opacity)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            switch transferState {
            case .sending:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Sending to camera…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            case .failed(let message):
                Label {
                    Text("GPS was not sent: \(message)")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .contentTransition(reduceMotion ? .identity : .opacity)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            case .idle, .sent:
                EmptyView()
            }
        }
    }

    private var statusTitle: String {
        switch status {
        case .off: "GPS off"
        case .waiting: "Waiting for location"
        case .servicesDisabled: "Location Services off"
        case .authorizationDenied: "Location access denied"
        case .requestingAuthorization: "Location access needed"
        case .accuracyLimited: "Precise Location needed"
        case .ready: "Location available"
        case .rejected: "Waiting for a better fix"
        case .failed: "Location unavailable"
        }
    }

    private var statusSymbol: String {
        switch status {
        case .ready: "location.fill"
        case .off, .servicesDisabled: "location.slash"
        case .waiting, .requestingAuthorization: "location"
        case .authorizationDenied, .accuracyLimited, .rejected, .failed: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .ready: .green
        case .authorizationDenied, .accuracyLimited, .rejected, .failed: .red
        default: .secondary
        }
    }

    private func coordinate(_ value: Double, positive: String, negative: String) -> String {
        guard value.isFinite else { return "Unavailable" }
        let number = abs(value).formatted(.number.grouping(.never).precision(.fractionLength(6)))
        return "\(number)° \(value < 0 ? negative : positive)"
    }

    private func accuracy(_ location: CLLocation) -> String {
        guard location.horizontalAccuracy.isFinite, location.horizontalAccuracy >= 0 else { return "Unavailable" }
        return "± \(location.horizontalAccuracy.formatted(.number.precision(.fractionLength(0)))) m"
    }

    private func altitude(_ location: CLLocation) -> String {
        guard location.verticalAccuracy.isFinite, location.verticalAccuracy >= 0,
              location.altitude.isFinite else { return "Unavailable" }
        return "\(location.altitude.formatted(.number.precision(.fractionLength(0)))) m"
    }
}

#if DEBUG
#Preview("GPS card") {
    NavigationStack {
        List {
            Section("GPS location") {
                GPSLocationCard(
                    location: CLLocation(
                        coordinate: CLLocationCoordinate2D(latitude: 31.230416, longitude: 121.473701),
                        altitude: 12,
                        horizontalAccuracy: 5,
                        verticalAccuracy: 3,
                        timestamp: .now
                    ),
                    status: .ready,
                    lastSentAt: .now,
                    transferState: .sent,
                    isLocationRunning: true,
                    canSendLocation: true,
                    sendLocation: {}
                )
            }
        }
        .navigationTitle("Nikon Smart GPS")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Waiting for GPS") {
    List {
        Section("GPS location") {
            GPSLocationCard(
                location: nil,
                status: .waiting,
                lastSentAt: nil,
                transferState: .idle,
                isLocationRunning: true,
                canSendLocation: false,
                sendLocation: {}
            )
        }
    }
}

#endif
