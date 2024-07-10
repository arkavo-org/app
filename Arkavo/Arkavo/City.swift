import Foundation
import CoreLocation
import SwiftUI

struct City: Identifiable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let population: Int
    let continent: String
    
    func serialize() -> Data {
        var data = Data()
        data.append(id.uuidData)
        let nameData = name.data(using: .utf8)!
        data.append(UInt16(nameData.count).bigEndian.data)
        data.append(nameData)
        data.append(coordinate.latitude.bitPattern.bigEndian.data)
        data.append(coordinate.longitude.bitPattern.bigEndian.data)
        data.append(UInt32(population).bigEndian.data)
        let continentData = continent.data(using: .utf8)!
        data.append(UInt16(continentData.count).bigEndian.data)
        data.append(continentData)
        return data
    }
    
    static func deserialize(from data: Data) -> City? {
        var data = data
        
        guard data.count >= 16 + 2 + 8 + 8 + 4 + 2 else { return nil }
        
        let idData = data.prefix(16)
        data = data.dropFirst(16)
        guard let id = UUID(uuidString: idData.map { String(format: "%02x", $0) }.joined()) else { return nil }
        
        let nameLength = Int(UInt16(bigEndian: data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) }))
        data = data.dropFirst(2)
        guard data.count >= nameLength + 8 + 8 + 4 + 2 else { return nil }
        guard let name = String(data: data.prefix(nameLength), encoding: .utf8) else { return nil }
        data = data.dropFirst(nameLength)
        
        let latitude = Double(bitPattern: UInt64(bigEndian: data.prefix(8).withUnsafeBytes { $0.load(as: UInt64.self) }))
        data = data.dropFirst(8)
        let longitude = Double(bitPattern: UInt64(bigEndian: data.prefix(8).withUnsafeBytes { $0.load(as: UInt64.self) }))
        data = data.dropFirst(8)
        
        let population = Int(UInt32(bigEndian: data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }))
        data = data.dropFirst(4)
        
        let continentLength = Int(UInt16(bigEndian: data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) }))
        data = data.dropFirst(2)
        guard data.count >= continentLength else { return nil }
        guard let continent = String(data: data.prefix(continentLength), encoding: .utf8) else { return nil }
        
        return City(id: id, name: name, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), population: population, continent: continent)
    }
}

extension UUID {
    var uuidData: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }
}

extension FixedWidthInteger {
    var data: Data {
        withUnsafeBytes(of: self.bigEndian) { Data($0) }
    }
}

public struct CityLabel: View {
    let name: String
    let population: Int
    
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.5
    
    public var body: some View {
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


func generateTwoThousandActualCities() -> [City] {
    // This function would typically load data from a file or database
    // For demonstration purposes, we'll generate a list programmatically
    // In a real scenario, you'd want to load this data from a reliable source
    
    var cities: [City] = []
    
    // List of actual cities with approximate populations
    let cityData: [(String, Double, Double, Int, String)] = [
        ("Tokyo", 35.6762, 139.6503, 37_400_000, "Asia"),
        ("Delhi", 28.7041, 77.1025, 30_290_000, "Asia"),
        ("Shanghai", 31.2304, 121.4737, 27_058_000, "Asia"),
        ("São Paulo", -23.5505, -46.6333, 22_043_000, "South America"),
        ("Mexico City", 19.4326, -99.1332, 21_782_000, "North America"),
        ("Cairo", 30.0444, 31.2357, 20_901_000, "Africa"),
        ("Mumbai", 19.0760, 72.8777, 20_411_000, "Asia"),
        ("Beijing", 39.9042, 116.4074, 20_384_000, "Asia"),
        ("Dhaka", 23.8103, 90.4125, 20_283_000, "Asia"),
        ("Osaka", 34.6937, 135.5023, 19_165_000, "Asia"),
        ("New York City", 40.7128, -74.0060, 18_804_000, "North America"),
        ("Karachi", 24.8607, 67.0011, 16_093_000, "Asia"),
        ("Buenos Aires", -34.6037, -58.3816, 15_369_000, "South America"),
        ("Chongqing", 29.4316, 106.9123, 15_354_000, "Asia"),
        ("Istanbul", 41.0082, 28.9784, 15_029_000, "Europe"),
        ("Kolkata", 22.5726, 88.3639, 14_850_000, "Asia"),
        ("Lagos", 6.5244, 3.3792, 14_368_000, "Africa"),
        ("Kinshasa", -4.4419, 15.2663, 14_342_000, "Africa"),
        ("Manila", 14.5995, 120.9842, 13_923_000, "Asia"),
        ("Tianjin", 39.3434, 117.3616, 13_400_000, "Asia"),
        ("Guangzhou", 23.1291, 113.2644, 13_301_000, "Asia"),
        ("Rio de Janeiro", -22.9068, -43.1729, 13_293_000, "South America"),
        ("Lahore", 31.5497, 74.3436, 12_642_000, "Asia"),
        ("Bangalore", 12.9716, 77.5946, 12_327_000, "Asia"),
        ("Moscow", 55.7558, 37.6173, 12_195_000, "Europe"),
        ("Shenzhen", 22.5431, 114.0579, 12_356_000, "Asia"),
        ("Jakarta", -6.2088, 106.8456, 10_562_000, "Asia"),
        ("London", 51.5074, -0.1278, 10_317_000, "Europe"),
        ("Paris", 48.8566, 2.3522, 10_927_000, "Europe"),
        ("Lima", -12.0464, -77.0428, 9_751_000, "South America"),
        ("Bangkok", 13.7563, 100.5018, 10_539_000, "Asia"),
        ("Hyderabad", 17.3850, 78.4867, 10_004_000, "Asia"),
        ("Seoul", 37.5665, 126.9780, 9_838_000, "Asia"),
        ("Nagoya", 35.1815, 136.9066, 9_546_000, "Asia"),
        ("Chennai", 13.0827, 80.2707, 10_971_000, "Asia"),
        ("Tehran", 35.6892, 51.3890, 9_135_000, "Asia"),
        ("Bogotá", 4.7110, -74.0721, 7_181_000, "South America"),
        ("Ho Chi Minh City", 10.8231, 106.6297, 8_637_000, "Asia"),
        ("Hong Kong", 22.3193, 114.1694, 7_482_000, "Asia"),
        ("Hanoi", 21.0285, 105.8542, 7_779_000, "Asia"),
        ("Johannesburg", -26.2041, 28.0473, 5_635_000, "Africa"),
        ("Sydney", -33.8688, 151.2093, 5_312_000, "Australia"),
        ("Singapore", 1.3521, 103.8198, 5_703_000, "Asia"),
        ("Los Angeles", 34.0522, -118.2437, 12_459_000, "North America"),
        ("Madrid", 40.4168, -3.7038, 6_618_000, "Europe"),
        ("Toronto", 43.651070, -79.347015, 6_196_000, "North America"),
        ("Berlin", 52.5200, 13.4050, 3_769_000, "Europe"),
        ("Riyadh", 24.7136, 46.6753, 7_676_000, "Asia"),
        ("Santiago", -33.4489, -70.6693, 6_269_000, "South America"),
        ("Baghdad", 33.3152, 44.3661, 6_962_000, "Asia"),
        ("Singapore", 1.3521, 103.8198, 5_638_000, "Asia"),
        ("Saint Petersburg", 59.9343, 30.3351, 5_398_000, "Europe"),
        ("Kuala Lumpur", 3.1390, 101.6869, 7_200_000, "Asia"),
        ("Abidjan", 5.3364, -4.0266, 5_170_000, "Africa"),
        ("Durban", -29.8587, 31.0218, 3_442_000, "Africa"),
        ("Accra", 5.6037, -0.1870, 2_291_000, "Africa"),
        ("Algiers", 36.7372, 3.0860, 3_919_000, "Africa"),
        ("Cape Town", -33.9249, 18.4241, 4_618_000, "Africa"),
        ("Casablanca", 33.5731, -7.5898, 3_360_000, "Africa"),
        ("Lisbon", 38.7223, -9.1393, 2_942_000, "Europe"),
        ("Riga", 56.9496, 24.1052, 632_000, "Europe"),
        ("Luxembourg City", 49.6116, 6.1319, 120_000, "Europe")
        // Add the rest of the cities up to 2000
    ]
    
    for (name, lat, lon, pop, continent) in cityData {
        cities.append(City(id: UUID(), name: name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), population: pop, continent: continent))
    }
    
    // Sort cities by population in descending order
    return cities.sorted { $0.population > $1.population }
}

// Usage
//let allCities = generateTwoThousandActualCities()
//print("Generated \(allCities.count) cities")
//print("Largest city: \(allCities[0].name) with population \(allCities[0].population)")
//print("Smallest city: \(allCities.last!.name) with population \(allCities.last!.population)")
//
//// Test serialization and deserialization
//if let firstCity = allCities.first {
//    let serialized = firstCity.serialize()
//    if let deserialized = City.deserialize(from: serialized) {
//        print("Deserialized city: \(deserialized.name), Population: \(deserialized.population)")
//    } else {
//        print("Deserialization failed")
//    }
//}
