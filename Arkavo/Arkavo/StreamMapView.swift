import MapKit
import OpenTDFKit
import SwiftUI

struct StreamMapView: View {
    @StateObject private var locationManager = MapLocationManager()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isTrackingUser = false
    @State private var mapUpdateTrigger = UUID()
    @State private var annotations: [AnnotationItem] = []
    @State private var isScanning = false
    @State private var showReportForm = false
    @State private var geofenceState: GeofenceState = .normal
    @State private var showPrompt = false
    @Environment(\.locale) var locale
    private let capitolCoordinate = CLLocationCoordinate2D(latitude: 38.8899, longitude: -77.0091)
    private let geofenceRadius: CLLocationDistance = 7500

    var promptContent: (icon: String, title: String, description: String) {
        switch geofenceState {
        case .normal:
            return ("checkmark.circle.fill", "Area Secure", "Normal operations in monitored zone")
        case .warning:
            return ("exclamationmark.triangle.fill", "Situation Report Filed", "Monitoring elevated in target area")
        case .alert:
            return ("exclamationmark.circle.fill", "Alert Status", "Critical activity detected in zone")
        }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition, interactionModes: .all) {
                ForEach(annotations) { item in
                    if item.isCluster {
                        Annotation(item.name, coordinate: item.coordinate) {
                            ClusterAnnotationView(count: item.count, continent: item.name)
                        }
                    } else {
                        Marker(item.name, coordinate: item.coordinate)
                    }
                }
                MapCircle(center: capitolCoordinate, radius: geofenceRadius)
                    .foregroundStyle(geofenceState.color.opacity(0.2))
                    .stroke(geofenceState.color, lineWidth: 2)
            }
            .mapStyle(.imagery(elevation: .realistic))
            .task {
                await showGlobeCenteredOnUserCountry()
                setupAnnotations()
            }
            // Scanning overlay
            if isScanning {
                CompactScanningOverlay(isScanning: $isScanning, geofenceState: $geofenceState)
                    .padding(.bottom, getDynamicIslandPadding())
            }
            if showPrompt {
                PromptCard(
                    icon: promptContent.icon,
                    title: promptContent.title,
                    description: promptContent.description,
                    geofenceState: geofenceState
                )
                .padding(.top, getDynamicIslandPadding())
            }
            if locationManager.statusString == "authorizedWhenInUse" || locationManager.statusString == "authorizedAlways" {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            showReportForm.toggle()
                        }) {
                            Image(systemName: "doc.text")
                                .font(.title2)
                                .padding()
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                        .padding()
                        Button(action: {
                            isScanning.toggle()
                        }) {
                            Image(systemName: isScanning ? "shield.fill" : "shield")
                                .font(.title2)
                                .padding()
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                        .padding()
                        Button(action: {
                            isTrackingUser.toggle()
                            if isTrackingUser {
                                centerOnUserLocation()
                            } else {
                                Task {
                                    await showGlobeCenteredOnUserCountry()
                                }
                            }
                        }) {
                            Image(systemName: isTrackingUser ? "location.fill" : "location")
                                .padding()
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                        .padding()
                    }
                }
            }
        }
        .sheet(isPresented: $showReportForm) {
            ReportFormView(isPresented: $showReportForm, geofenceState: $geofenceState)
        }
        .onChange(of: geofenceState) { oldState, newState in
            withAnimation {
                showPrompt = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                withAnimation {
                    showPrompt = false
                }
            }
        }
    }

    private func getDynamicIslandPadding() -> CGFloat {
        60 // Additional padding for Dynamic Island
    }

    private func setupAnnotations() {
        if let userLocation = locationManager.lastLocation?.coordinate {
            annotations.append(AnnotationItem(
                coordinate: userLocation,
                name: "Asset",
                count: 1,
                isCluster: false
            ))
        }
    }

    private func centerOnUserLocation() {
        if let userLocation = locationManager.lastLocation?.coordinate {
            withAnimation {
                cameraPosition = .camera(MapCamera(
                    centerCoordinate: userLocation,
                    distance: 1000, // Adjust this value to change the zoom level
                    heading: 0,
                    pitch: 0
                ))
            }
        } else {
            // Fallback if user location is not available
            cameraPosition = .userLocation(fallback: cameraPosition)
        }
    }

    private func showGlobeCenteredOnUserCountry() async {
        let centerCoordinate = await getCountryCenterCoordinate()
        cameraPosition = .camera(MapCamera(
            centerCoordinate: centerCoordinate,
            distance: 40_000_000,
            heading: 0,
            pitch: 0
        ))
    }

    private func getCountryCenterCoordinate() async -> CLLocationCoordinate2D {
        let countryCode = locale.region?.identifier ?? "US"
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(countryCode)
            return (placemarks.first?.location!.coordinate)!
        } catch {
            print("Geocoding failed: \(error.localizedDescription)")
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
    }

    private func engageAction() async {
        let centerCoordinate = await getCountryCenterCoordinate()
        var currentCenter = centerCoordinate
        if cameraPosition.camera != nil {
            currentCenter = cameraPosition.camera!.centerCoordinate
        }
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: currentCenter,
                distance: 400_000,
                heading: 0,
                pitch: 0
            ))
        }
        // FIXME: Switch to word cloud view
    }

    private var mapDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let delta = value.translation
                withAnimation {
                    cameraPosition = MapCameraPosition.camera(
                        MapCamera(
                            centerCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                            distance: 40_000_000,
                            heading: delta.width,
                            pitch: delta.height
                        )
                    )
                }
            }
    }
}

enum GeofenceState {
    case normal
    case warning
    case alert
    
    var color: Color {
        switch self {
        case .normal:
            return .green
        case .warning:
            return .yellow
        case .alert:
            return .red
        }
    }
}

struct PromptCard: View {
    let icon: String
    let title: String
    let description: String
    let geofenceState: GeofenceState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(geofenceState.color)
                .font(.system(size: 24))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(geofenceState.color)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(geofenceState.color.opacity(0.1))
        .cornerRadius(12)
        .transition(.move(edge: .top))
    }
}

class MapLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var locationStatus: CLAuthorizationStatus?
    @Published var lastLocation: CLLocation?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    var statusString: String {
        guard let status = locationStatus else {
            return "unknown"
        }
        switch status {
        case .notDetermined: return "notDetermined"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        case .authorizedAlways: return "authorizedAlways"
        case .restricted: return "restricted"
        case .denied: return "denied"
        @unknown default: return "unknown"
        }
    }

    func locationManager(_: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        locationStatus = status
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
    }
}

struct ClusterAnnotationView: View {
    let count: Int
    let continent: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.7))
                .frame(width: 50, height: 50)
            VStack {
                Text("\(count)")
                    .font(.system(size: 14, weight: .bold))
                Text(continent)
                    .font(.system(size: 10))
            }
            .foregroundColor(.white)
        }
    }
}

struct IdentifiableMapAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let content: AnyView

    init(coordinate: CLLocationCoordinate2D, @ViewBuilder content: () -> some View) {
        self.coordinate = coordinate
        self.content = AnyView(content())
    }
}

struct AnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let name: String
    let count: Int
    let isCluster: Bool
}

struct CompactScanningOverlay: View {
    @Binding var isScanning: Bool
    @Binding var geofenceState: GeofenceState
    @State private var progress: [String: CGFloat] = ["reddit": 0.0]
    @State private var isPaused = false

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundColor(.arkavoBrand)
                    Text("Scanning in Progress")
                        .font(.headline)
                        .foregroundColor(.arkavoText)
                    Spacer()
                    Button(action: {
                        isPaused.toggle()
                    }) {
                        Text(isPaused ? "Resume" : "Pause")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.arkavoBrand)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.arkavoBrandLight)
                            .clipShape(Capsule())
                    }
                }

                ForEach(Array(progress.keys), id: \.self) { network in
                    VStack(spacing: 4) {
                        HStack {
                            Text(network.capitalized)
                                .font(.subheadline)
                                .foregroundColor(.arkavoSecondary)
                            Spacer()
                            Text("\(Int(progress[network]! * 100))%")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.arkavoText)
                        }

                        ProgressView(value: progress[network])
                            .tint(.orange)
                    }
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(16)
            .shadow(radius: 10)
            .padding()
        }
        .onAppear {
            startProgressSimulation()
        }
    }

    private func startProgressSimulation() {
        // Simulated progress updates
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            guard !isPaused else { return }

            withAnimation(.linear(duration: 0.1)) {
                for network in progress.keys {
                    if progress[network]! < 1.0 {
                        progress[network]! += 0.05
                    }
                }
                // Stop timer when all networks reach 100%
                if progress.values.allSatisfy({ $0 >= 1.0 }) {
                    timer.invalidate()
                    isScanning = false
                    geofenceState = .alert // Set geofence to red after scan completes
                }
            }
        }
    }
}

// Preview provider
struct StreamMapView_Previews: PreviewProvider {
    static var previews: some View {
        StreamMapView()
    }
}


struct ReportFormView: View {
    @Binding var isPresented: Bool
    @Binding var geofenceState: GeofenceState
    @State private var reportText: String = """
SITUATION REPORT - POTOMAC RIVER
DTG: 151300NOV24
Heavy rains over the past 48 hours have raised the Potomac River water levels 2.5 feet above normal, causing moderate flooding at Fletcher's Boathouse and Thompson's Boat Center with debris accumulation observed near Key Bridge and Roosevelt Bridge. Commercial barge traffic is operating at 60% capacity due to enhanced safety protocols, while recreational boating has been temporarily suspended between Chain Bridge and Woodrow Wilson Bridge. Water treatment facilities are reporting increased turbidity but maintaining normal operations despite the conditions.
"""
    
    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: $reportText)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.gray))
                    .cornerRadius(8)
                    .padding()
            }
            .navigationTitle("Situation Report")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Submit") {
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation {
                                geofenceState = .warning
                            }
                        }
                    }
                }
            }
        }
    }
}
