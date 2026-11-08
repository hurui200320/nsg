import SwiftUI
import MapKit
import Network

enum MapLoadingState: Equatable {
    case loading
    case loaded
    case failed
}

/// A usable network path alone does not prove that MapKit can retrieve its tiles.
enum MapConnectivityStatus: Hashable {
    case checking
    case loading
    case available
    case offline
    case unavailable

    static func resolve(networkAvailable: Bool?, loadingState: MapLoadingState) -> Self {
        if networkAvailable == false { return .offline }
        if loadingState == .failed { return .unavailable }
        guard networkAvailable == true else { return .checking }
        return loadingState == .loaded ? .available : .loading
    }

    var symbol: String {
        switch self {
        case .offline: "wifi.slash"
        case .unavailable: "wifi.exclamationmark"
        default: "wifi"
        }
    }

    var message: String {
        switch self {
        case .checking: "Checking map network availability."
        case .loading: "Network connected. Loading map data."
        case .available: "Network connected. Map data available."
        case .offline: "No network connection. Cached maps may still be visible. GPS works independently."
        case .unavailable: "Map data could not be loaded. GPS works independently."
        }
    }

    var color: Color {
        switch self {
        case .available: .green
        case .offline, .unavailable: .orange
        case .loading, .checking: .secondary
        }
    }
}

struct GPSMapView: View {
    let location: CLLocation?
    var allowsInteraction = false
    var extendsToEdges = false
    var showsConnectivityIndicator = true

    @State private var isNetworkAvailable: Bool?
    @State private var loadingState: MapLoadingState = .loading

    private var connectivityStatus: MapConnectivityStatus {
        .resolve(networkAvailable: isNetworkAvailable, loadingState: loadingState)
    }

    var body: some View {
        GPSMapContent(location: location, allowsInteraction: allowsInteraction) { state in
            loadingState = state
        }
        // Extend only the map; keep connectivity overlays inside the safe area.
        .ignoresSafeArea(.container, edges: extendsToEdges ? .all : [])
        .overlay(alignment: .topLeading) {
            if showsConnectivityIndicator {
                Image(systemName: connectivityStatus.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(connectivityStatus.color)
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial, in: Circle())
                    .padding(12)
                    .accessibilityLabel(connectivityStatus.message)
                    .help(connectivityStatus.message)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if GPSMapContent.displayCoordinate(for: location) == nil {
                Label("No location available", systemImage: "location.slash")
                    .font(.caption)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
            }
        }
        .task(id: showsConnectivityIndicator) {
            guard showsConnectivityIndicator else { return }
            // Observe Wi-Fi AND cellular paths; the Wi-Fi glyph represents map connectivity.
            let monitor = NWPathMonitor()
            defer { monitor.cancel() }
            for await path in monitor {
                guard !Task.isCancelled else { break }
                isNetworkAvailable = path.status == .satisfied
            }
        }
    }
}

struct GPSMapPage: View {
    @Environment(\.dismiss) private var dismiss
    let location: CLLocation?

    var body: some View {
        NavigationStack {
            GPSMapView(
                location: location,
                allowsInteraction: true,
                extendsToEdges: true,
                showsConnectivityIndicator: false
            )
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }
}

/// MKMapView supplies tile-loading callbacks that SwiftUI's Map does not expose.
private struct GPSMapContent: UIViewRepresentable {
    let location: CLLocation?
    let allowsInteraction: Bool
    let onLoadingStateChange: (MapLoadingState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoadingStateChange: onLoadingStateChange)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = configuration
        map.showsCompass = false
        map.showsScale = false
        map.showsUserTrackingButton = false
        map.selectableMapFeatures = []
        // Use only the converted custom marker; do not add a second native location marker.
        map.showsUserLocation = false
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.isScrollEnabled = allowsInteraction
        map.isZoomEnabled = allowsInteraction
        map.isRotateEnabled = allowsInteraction
        map.isPitchEnabled = allowsInteraction
        context.coordinator.onLoadingStateChange = onLoadingStateChange
        context.coordinator.updateLocation(
            Self.displayCoordinate(for: location),
            on: map,
            followsLocation: !allowsInteraction
        )
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.isActive = false
        map.delegate = nil
        map.showsUserLocation = false
    }

    static func displayCoordinate(for location: CLLocation?) -> CLLocationCoordinate2D? {
        guard let location else { return nil }
        // TEMPORARY OVERRIDE: Force WGS-84 -> GCJ-02 for map display without
        // detecting Apple's active basemap. Non-GCJ-02 basemaps may be misaligned.
        // Convert the original GPS fix exactly once for both the marker and camera.
        // Never send this display coordinate to the numeric UI or Nikon GEO payload.
        return GCJ02CoordinateConverter.fromWGS84(location.coordinate)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onLoadingStateChange: (MapLoadingState) -> Void
        var isActive = true
        private var annotation: MKPointAnnotation?
        private var hasCentered = false

        init(onLoadingStateChange: @escaping (MapLoadingState) -> Void) {
            self.onLoadingStateChange = onLoadingStateChange
        }

        func updateLocation(_ coordinate: CLLocationCoordinate2D?, on map: MKMapView, followsLocation: Bool) {
            guard let coordinate else {
                if let annotation {
                    map.removeAnnotation(annotation)
                    self.annotation = nil
                }
                hasCentered = false
                return
            }

            let coordinateChanged = annotation?.coordinate.latitude != coordinate.latitude ||
                annotation?.coordinate.longitude != coordinate.longitude
            if let annotation {
                if coordinateChanged { annotation.coordinate = coordinate }
            } else {
                let annotation = MKPointAnnotation()
                annotation.coordinate = coordinate
                annotation.title = "Phone location"
                self.annotation = annotation
                map.addAnnotation(annotation)
            }

            if !hasCentered {
                map.setRegion(
                    MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800),
                    animated: false
                )
                hasCentered = true
            } else if followsLocation && coordinateChanged {
                map.setCenter(coordinate, animated: false)
            }
            // Expanded maps update the marker without undoing the user's pan or zoom.
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard annotation === self.annotation else { return nil }
            let identifier = "phoneLocation"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ??
                MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
            view.backgroundColor = .systemBlue
            view.layer.cornerRadius = 10
            view.layer.borderWidth = 3
            view.layer.borderColor = UIColor.white.cgColor
            view.layer.shadowColor = UIColor.black.cgColor
            view.layer.shadowOpacity = 0.15
            view.layer.shadowRadius = 3
            view.layer.shadowOffset = CGSize(width: 0, height: 1)
            view.canShowCallout = false
            view.isEnabled = false
            view.isDraggable = false
            view.isAccessibilityElement = true
            view.accessibilityLabel = "Phone location"
            return view
        }

        func mapViewWillStartLoadingMap(_ mapView: MKMapView) {
            report(.loading)
        }

        func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
            report(.loaded)
        }

        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: any Error) {
            report(.failed)
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            report(fullyRendered ? .loaded : .failed)
        }

        private func report(_ state: MapLoadingState) {
            // MapKit may call back during a representable update; publish on the next actor turn.
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.onLoadingStateChange(state)
            }
        }
    }
}

#if DEBUG
#Preview("Location map") {
    GPSMapPage(location: CLLocation(latitude: 31.230416, longitude: 121.473701))
}

#Preview("Connectivity indicators") {
    HStack(spacing: 24) {
        ForEach(
            [MapConnectivityStatus.checking, .loading, .available, .offline, .unavailable],
            id: \.self
        ) { status in
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
                .accessibilityLabel(status.message)
        }
    }
    .padding()
}
#endif
