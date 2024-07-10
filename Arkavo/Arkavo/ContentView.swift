import SwiftUI
import SwiftData
import MapKit
import CryptoKit
import OpenTDFKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    let webSocket = KASWebSocket(kasUrl: URL(string: "wss://kas.arkavo.net")!)
    let nanoTDFManager = NanoTDFManager()
    @State private var kasPublicKey: P256.KeyAgreement.PublicKey?
    @State private var position = MapCameraPosition.region(MKCoordinateRegion(
// Columbia 39.21579° N, 76.86180° W
// Virtru   38.90059° N, 77.04209° W
        center: CLLocationCoordinate2D(latitude: 38.90059, longitude: -77.04209),
        span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)
    ))
    @State private var cities: [City] = []
    @State private var showingCities: [City] = []
    @State private var nanoCities: [NanoTDF] = []
   
    var body: some View {
        NavigationSplitView {
            VStack {
                VStack {
                    Button(action: loadGeoJSON) {
                        Label("Prepare", systemImage: "pencil")
                    }
                    Button(action: createNanoCities) {
                        Label("Nano", systemImage: "network")
                    }
                    Button(action: animateCities) {
                        Label("Display", systemImage: "eye")
                    }
                    Button(action: addItem) {
                        Label("Add", systemImage: "plus")
                    }
#if os(iOS)
                    EditButton()
#endif
                }
                List {
                    ForEach(items) { item in
                        NavigationLink {
                            Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                        } label: {
                            Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
                .onAppear {
                    webSocket.setKASPublicKeyCallback{ publicKey in
                        print("setKASPublicKeyCallback")
                        kasPublicKey = publicKey
                    }
                    webSocket.setRewrapCallback { id, symmetricKey in
                        print("id in \(id)")
                        let nanoCity = nanoTDFManager.getNanoTDF(withIdentifier: id)
                        nanoTDFManager.removeNanoTDF(withIdentifier: id)
                        guard symmetricKey != nil else {
                            print("DENY")
                            // DENY
                            return
                        }
                        do {
                            let payload = try nanoCity?.getPayloadPlaintext(symmetricKey: symmetricKey!)
                            guard payload != nil else {
                                print("payload decrypt failed")
                                return
                            }
                            let city = City.deserialize(from: payload!)
                            guard city != nil else {
                                print("city deserialize failed")
                                return
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0...2)) {
                                showingCities.append(city!)
                                // FIXME id
                                //                            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration(for: city!)) {
                                //                                showingCities.removeAll { $0.id == city.id }
                                //                            }
                            }
                        } catch {
                            print("getPayloadPlaintext failed")
                        }
                    }
                    webSocket.connect()
                    webSocket.sendPublicKey()
                    webSocket.sendKASKeyMessage()
                }
#if os(macOS)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
            }
        } detail: {
            ZStack {
                Map(position: $position) {
                    ForEach(showingCities) { city in
                        Annotation(city.name, coordinate: city.coordinate) {
                            CityLabel(name: city.name, population: city.population)
                        }
                    }
                }
                .mapStyle(.imagery)
                .edgesIgnoringSafeArea(.all)
                
                VStack {
                    Spacer()
                    Text("Cities shown: \(showingCities.count)")
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                }
            }
        }
    }
    
    private func loadGeoJSON() {
        print("Loading GeoJSON...")
        cities = generateTwoThousandActualCities()
        print("Cities loaded: \(cities.count)")
    }
    
    private func createNanoCities() {
        print("Nanoing Cities...")
        guard kasPublicKey != nil else {
            print("KAS public key")
            return
        }
        let dispatchGroup = DispatchGroup()
        let queue = DispatchQueue(label: "com.arkavo.nanoTDFCreation", attributes: .concurrent)
        
        for city in cities {
            dispatchGroup.enter()
            queue.async {
                do {
                    let serializedCity = city.serialize()
                    let kasRL = ResourceLocator(protocolEnum: .wss, body: "kas.arkavo.net")
                    let kasMetadata = KasMetadata(resourceLocator: kasRL!, publicKey: kasPublicKey!, curve: .secp256r1)
                    let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "5GnJAVumy3NBdo2u9ZEK1MQAXdiVnZWzzso4diP2JszVgSJQ")
                    var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)
                    
                    let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: serializedCity)
                    
                    DispatchQueue.main.async {
                        self.nanoCities.append(nanoTDF)
                        dispatchGroup.leave()
                    }
                } catch {
                    print("Error creating nanoTDF for \(city.name): \(error)")
                    dispatchGroup.leave()
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            print("Cities nanoed: \(self.nanoCities.count)")
        }
    }
    
    private func animateCities() {
        print("Rewrapping...")
        for nanoCity in nanoCities {
            let id = nanoCity.header.ephemeralPublicKey
            nanoTDFManager.addNanoTDF(nanoCity, withIdentifier: id)
            webSocket.sendRewrapMessage(header: nanoCity.header)
            print("id out \(id)")
//            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0...2)) {
//                showingCities.append(city)
//                
//                DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration(for: city)) {
//                    showingCities.removeAll { $0.id == city.id }
//                }
//            }
        }
    }
    
    private func animationDuration(for city: City) -> Double {
        // Base duration on population. Adjust these values as needed.
        0.4
//        let baseDuration = 1.0
//        let populationFactor = Double(city.population) / 1_000_000.0 // Cities with 1 million+ get longer durations
//        return baseDuration + (populationFactor * 5) // Max duration of 5 seconds for very large cities
    }
    
    private func addItem() {
            let plaintext = "Keep this message secret".data(using: .utf8)!
            webSocket.setRewrapCallback { identifier, symmetricKey in
                defer {
                    print("END setRewrapCallback")
                }
                print("BEGIN setRewrapCallback")
                print("Received Rewrapped Symmetric key: \(String(describing: symmetricKey))")
            }
            webSocket.setKASPublicKeyCallback { publicKey in
                let kasRL = ResourceLocator(protocolEnum: .http, body: "localhost:8080")
                let kasMetadata = KasMetadata(resourceLocator: kasRL!, publicKey: publicKey, curve: .secp256r1)
                let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "localhost/123")
                var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)

                do {
                    // create
                    let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: plaintext)
                    print("Encryption successful")
                    webSocket.sendRewrapMessage(header: nanoTDF.header)
                } catch {
                    print("Error creating nanoTDF: \(error)")
                }
            }
            webSocket.connect()
            webSocket.sendPublicKey()
            webSocket.sendKASKeyMessage()
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}

class NanoTDFManager {
    private var nanoTDFs: [Data: NanoTDF] = [:]
    private var count: Int = 0

    func addNanoTDF(_ nanoTDF: NanoTDF, withIdentifier identifier: Data) {
        nanoTDFs[identifier] = nanoTDF
        count += 1
    }

    func getNanoTDF(withIdentifier identifier: Data) -> NanoTDF? {
        nanoTDFs[identifier]
    }

    func updateNanoTDF(_ nanoTDF: NanoTDF, withIdentifier identifier: Data) {
        nanoTDFs[identifier] = nanoTDF
    }

    func removeNanoTDF(withIdentifier identifier: Data) {
        if nanoTDFs.removeValue(forKey: identifier) != nil {
            count -= 1
        }
    }

    func isEmpty() -> Bool {
        return nanoTDFs.isEmpty
    }

    func getCount() -> Int {
        return count
    }
}
