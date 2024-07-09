import SwiftUI
import SwiftData
import MapKit
import CryptoKit
import OpenTDFKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    let webSocket = KASWebSocket(kasUrl: URL(string: "wss://kas.arkavo.net")!)
    
    @State private var position = MapCameraPosition.region(MKCoordinateRegion(
// Columbia 39.21579° N, 76.86180° W
// Virtru   38.90059° N, 77.04209° W
        center: CLLocationCoordinate2D(latitude: 38.90059, longitude: -77.04209),
        span: MKCoordinateSpan(latitudeDelta: 25, longitudeDelta: 25)
    ))
    @State private var cities: [City] = []
    @State private var showingCities: [City] = []
   
    var body: some View {
        NavigationSplitView {
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
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                #endif
                ToolbarItem {
                    Button(action: loadGeoJSON) {
                        Label("Add Item", systemImage: "plus")
                    }
                    Button(action: animateCities) {
                        Label("Add Item", systemImage: "minus")
                    }
                }
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
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(10)
                }
            }
        }
    }
    
    private func loadGeoJSON() {
        print("Loading GeoJSON...")
        // This is a placeholder function. In a real app, you'd parse actual GeoJSON data.
        let sampleCities = [
            City(name: "San Francisco", coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), population: 873965),
            City(name: "Los Angeles", coordinate: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437), population: 3898747),
            City(name: "San Diego", coordinate: CLLocationCoordinate2D(latitude: 32.7157, longitude: -117.1611), population: 1386932),
            City(name: "Columbia", coordinate: CLLocationCoordinate2D(latitude: 39.21579, longitude: -77.04209), population: 100000)
        ]
        
        cities = sampleCities
        animateCities()
        print("Cities loaded: \(cities.count)")
    }
    
    private func animateCities() {
        print("Loading GeoJSON...")
        for city in cities {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0...2)) {
                showingCities.append(city)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration(for: city)) {
                    showingCities.removeAll { $0.id == city.id }
                }
            }
        }
    }
    
    private func animationDuration(for city: City) -> Double {
        // Base duration on population. Adjust these values as needed.
        let baseDuration = 2.0
        let populationFactor = Double(city.population) / 1_000_000.0 // Cities with 1 million+ get longer durations
        return baseDuration + (populationFactor * 3.0) // Max duration of 5 seconds for very large cities
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

struct City: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let population: Int
}

struct CityLabel: View {
    let name: String
    let population: Int
    
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.5
    
    var body: some View {
        Text(name)
            .font(.system(size: fontSize))
            .foregroundColor(.blue)
            .opacity(opacity)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: animationDuration)) {
                    opacity = 1
                    scale = 1
                }
                withAnimation(.easeInOut(duration: animationDuration).delay(animationDuration * 0.5)) {
                    opacity = 0
                    scale = maxScale
                }
            }
    }
    
    private var animationDuration: Double {
        Double(population) / 500_000.0 + 1.0 // 1 second for small cities, up to 5+ seconds for large ones
    }
    
    private var fontSize: CGFloat {
        CGFloat(population) / 100_000.0 + 12 // 12pt for small cities, larger for bigger ones
    }
    
    private var maxScale: CGFloat {
        (CGFloat(population) / 500_000.0) + 1.5 // 1.5x for small cities, larger for bigger ones
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
