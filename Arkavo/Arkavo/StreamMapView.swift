import MapKit
import OpenTDFKit
import SwiftUI

struct StreamMapView: View {
//    @StateObject private var locationManager = MapLocationManager()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isTrackingUser = false
    @State private var mapUpdateTrigger = UUID()
    @State private var annotations: [AnnotationItem] = []
    @Environment(\.locale) var locale

    var body: some View {
        ZStack {
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
            }
            .mapStyle(.imagery(elevation: .realistic))
            .task {
                await showGlobeCenteredOnUserCountry()
            }
//            if locationManager.statusString == "authorizedWhenInUse" || locationManager.statusString == "authorizedAlways" {
//                VStack {
//                    Spacer()
//                    HStack {
//                        Spacer()
//                        Button(action: {
//                            isTrackingUser.toggle()
//                            if isTrackingUser {
//                                centerOnUserLocation()
//                            } else {
//                                Task {
//                                    await showGlobeCenteredOnUserCountry()
//                                }
//                            }
//                        }) {
//                            Image(systemName: isTrackingUser ? "location.fill" : "location")
//                                .padding()
//                                .clipShape(Circle())
//                                .shadow(radius: 2)
//                        }
//                        .padding()
//                    }
//                }
//            }
        }
    }

//    private func centerOnUserLocation() {
//        if let userLocation = locationManager.lastLocation?.coordinate {
//            withAnimation {
//                cameraPosition = .camera(MapCamera(
//                    centerCoordinate: userLocation,
//                    distance: 1000, // Adjust this value to change the zoom level
//                    heading: 0,
//                    pitch: 0
//                ))
//            }
//        } else {
//            // Fallback if user location is not available
//            cameraPosition = .userLocation(fallback: cameraPosition)
//        }
//    }

    private func showGlobeCenteredOnUserCountry() async {
        let centerCoordinate = await getCountryCenterCoordinate()
        cameraPosition = .camera(MapCamera(
            centerCoordinate: centerCoordinate,
            distance: 40_000_000,
            heading: 0,
            pitch: 0,
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
                pitch: 0,
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
                            pitch: delta.height,
                        ),
                    )
                }
            }
    }
}

// class MapLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
//    private let locationManager = CLLocationManager()
//    @Published var locationStatus: CLAuthorizationStatus?
//    @Published var lastLocation: CLLocation?
//
//    override init() {
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//
//    var statusString: String {
//        guard let status = locationStatus else {
//            return "unknown"
//        }
//        switch status {
//        case .notDetermined: return "notDetermined"
//        case .authorizedWhenInUse: return "authorizedWhenInUse"
//        case .authorizedAlways: return "authorizedAlways"
//        case .restricted: return "restricted"
//        case .denied: return "denied"
//        @unknown default: return "unknown"
//        }
//    }
//
//    func locationManager(_: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
//        locationStatus = status
//    }
//
//    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        guard let location = locations.last else { return }
//        lastLocation = location
//    }
// }

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
