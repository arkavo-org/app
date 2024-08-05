import Foundation
import CoreLocation

struct City: Identifiable, Codable {
    let id: UUID
    let name: String
    let coordinate: Coordinate
    let population: Int
    let continent: String
    
    struct Coordinate: Codable {
        let latitude: Double
        let longitude: Double
        
        init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
        
        init(_ coordinate: CLLocationCoordinate2D) {
            self.latitude = coordinate.latitude
            self.longitude = coordinate.longitude
        }
        
        var clCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
    
    var clCoordinate: CLLocationCoordinate2D {
        coordinate.clCoordinate
    }
    
    init(id: UUID = UUID(), name: String, coordinate: CLLocationCoordinate2D, population: Int, continent: String) {
        self.id = id
        self.name = name
        self.coordinate = Coordinate(coordinate)
        self.population = population
        self.continent = continent
    }
    
    // Reuse encoder and decoder for better performance
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()
    
    private static let decoder = PropertyListDecoder()
    
    func serialize() throws -> Data {
        try City.encoder.encode(self)
    }
    
    static func deserialize(from data: Data) throws -> City {
        try decoder.decode(City.self, from: data)
    }
}

// Example usage
extension City {
    static func example() -> City {
        City(name: "New York",
             coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
             population: 8_419_000,
             continent: "North America")
    }
}
