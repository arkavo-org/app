import CryptoKit
import MapKit
import OpenTDFKit
import SwiftUI

struct StreamMapView: View {
    @ObservedObject var webSocketManager: WebSocketManager
    @ObservedObject var nanoTDFManager: NanoTDFManager
    @Binding var kasPublicKey: P256.KeyAgreement.PublicKey?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mapUpdateTrigger = UUID()
    @State private var cities: [City] = []
    @State private var nanoCities: [NanoTDF] = []
    @State private var nanoTime: TimeInterval = 0
    @StateObject private var annotationManager = AnnotationManager()
    @State private var inProcessCount = 0
    @State private var continentClusters: [String: [City]] = [:]
    @State private var annotations: [AnnotationItem] = []
    @State private var cityCount = 0
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
            // TODO: move to diagnostic view
//            VStack {
//                Spacer()
//                    PerformanceInfoOverlay(
//                        nanoTime: nanoTime,
//                        nanoCitiesCount: nanoCities.count,
//                        citiesCount: cities.count,
//                        decryptTime: nanoTDFManager.processDuration,
//                        decryptCount: nanoTDFManager.inProcessCount
//                    )
//                    .padding()
//            }
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

    func loadGeoJSON() {
        cities = generateTwoThousandActualCities()
        createNanoCities()
    }

    private func createNanoCities() {
        print("Nanoing Cities...")
        guard kasPublicKey != nil else {
            print("Missing KAS public key")
            return
        }
        let startTime = Date()
        let dispatchGroup = DispatchGroup()
        let queue = DispatchQueue(label: "com.arkavo.nanoTDFCreation", attributes: .concurrent)

        for city in cities {
            dispatchGroup.enter()
            queue.async {
                do {
                    let serializedCity = try city.serialize()
                    let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")
                    let kasMetadata = KasMetadata(resourceLocator: kasRL!, publicKey: kasPublicKey!, curve: .secp256r1)
                    let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: city.continent)
                    var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)

                    let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: serializedCity)

                    DispatchQueue.main.async {
                        nanoCities.append(nanoTDF)
                        dispatchGroup.leave()
                    }
                } catch {
                    print("Error creating nanoTDF for \(city.name): \(error)")
                    dispatchGroup.leave()
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            let endTime = Date()
            nanoTime = endTime.timeIntervalSince(startTime)
            sendCities()
        }
    }

    private func sendCities() {
        print("Sending...")
        let maxCitiesToSend = 3000
        let citiesToSend = nanoCities.prefix(maxCitiesToSend)
        for nanoCity in citiesToSend {
            let natsMessage = NATSMessage(payload: nanoCity.toData())
            let messageData = natsMessage.toData()

            webSocketManager.sendCustomMessage(messageData) { error in
                if let error {
                    print("Error sending thought: \(error)")
                }
            }
        }
    }

    func addCityToCluster(_ city: City) {
        if continentClusters[city.continent] == nil {
            continentClusters[city.continent] = []
        }
        continentClusters[city.continent]?.append(city)
        cityCount += 1
        updateAnnotations()
    }

    func removeCityFromCluster(_ city: City) {
        continentClusters[city.continent]?.removeAll { $0.id == city.id }
        cityCount -= 1
        updateAnnotations()
    }

    private func updateAnnotations() {
        annotations = continentClusters.flatMap { continent, cities -> [AnnotationItem] in
            if cities.count > 50 {
                let centerCoordinate = calculateCenterCoordinate(for: cities)
                return [AnnotationItem(coordinate: centerCoordinate, name: continent, count: cities.count, isCluster: true)]
            } else {
                return cities.map { city in
                    AnnotationItem(coordinate: city.clCoordinate, name: city.name, count: 1, isCluster: false)
                }
            }
        }
        mapUpdateTrigger = UUID()
    }

    private func calculateCenterCoordinate(for cities: [City]) -> CLLocationCoordinate2D {
        let totalLat = cities.reduce(0.0) { $0 + $1.coordinate.latitude }
        let totalLon = cities.reduce(0.0) { $0 + $1.coordinate.longitude }
        let count = Double(cities.count)
        return CLLocationCoordinate2D(latitude: totalLat / count, longitude: totalLon / count)
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

    private var diagnosticOverlay: some View {
        PerformanceInfoOverlay(
            nanoTime: nanoTime,
            nanoCitiesCount: nanoCities.count,
            citiesCount: cities.count,
            decryptTime: nanoTDFManager.processDuration,
            decryptCount: nanoTDFManager.inProcessCount
        )
        .padding()
    }

    func loadRandomCities() {
        nanoTime = 0
        nanoCities = []
        print("Generating new random cities...")
        let newCities = generateRandomCities(count: 1000)
        cities.append(contentsOf: newCities)
        print("New cities added: \(newCities.count)")
        print("Total cities: \(cities.count)")
        createNanoCities()
    }
}

class AnnotationManager: ObservableObject {
    @Published var annotations: [CityAnnotation] = []

    func addAnnotation(_ city: City) {
        DispatchQueue.main.async {
            if !self.annotations.contains(where: { $0.id == city.id }) {
                self.annotations.append(CityAnnotation(city: city))
            }
        }
    }

    func removeAnnotation(_ city: City) {
        DispatchQueue.main.async {
            self.annotations.removeAll { $0.id == city.id }
        }
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

struct CityAnnotationView: View {
    let city: City

    var body: some View {
        VStack {
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(.red)
                .font(.title)
            Text(city.name)
                .font(.caption)
                .fixedSize()
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
