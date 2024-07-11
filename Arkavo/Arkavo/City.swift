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
    
    init(id: UUID, name: String, coordinate: CLLocationCoordinate2D, population: Int, continent: String) {
        self.id = id
        self.name = name
        self.coordinate = Coordinate(coordinate)
        self.population = population
        self.continent = continent
    }
    
    func serialize() throws -> Data {
        try JSONEncoder().encode(self)
    }
    
    static func deserialize(from data: Data) throws -> City {
        try JSONDecoder().decode(City.self, from: data)
    }
}
