import CoreLocation

struct LocationData: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double

    init(location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<LocationData, Error>?
    @Published var lastLocation: LocationData?
    @Published var locationStatus: CLAuthorizationStatus?
    @Published var lastLocationError: Error?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }

    func requestLocationAsync() async throws -> LocationData {
        try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            self.requestLocation()
        }
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let locationData = LocationData(location: location)
        lastLocation = locationData
        print("Location: \(locationData.latitude), \(locationData.longitude), \(locationData.altitude)")
        locationContinuation?.resume(returning: locationData)
        locationContinuation = nil
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        print("Location Error: \(error.localizedDescription)")
        lastLocationError = error
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationStatus = manager.authorizationStatus
    }
}
