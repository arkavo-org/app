import XCTest
import CoreLocation
@testable import Arkavo

class CityTests: XCTestCase {

    func testInitialization() {
        let id = UUID()
        let coordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let city = City(id: id, name: "New York", coordinate: coordinate, population: 8_419_000, continent: "North America")
        
        XCTAssertEqual(city.id, id)
        XCTAssertEqual(city.name, "New York")
        XCTAssertEqual(city.coordinate.latitude, 40.7128, accuracy: 0.000001)
        XCTAssertEqual(city.coordinate.longitude, -74.0060, accuracy: 0.000001)
        XCTAssertEqual(city.population, 8_419_000)
        XCTAssertEqual(city.continent, "North America")
    }

    func testSerializeAndDeserialize() throws {
        let originalCity = City(id: UUID(), name: "New York", coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), population: 8_419_000, continent: "North America")
        
        let serializedData = try originalCity.serialize()
        let deserializedCity = try City.deserialize(from: serializedData)
        
        XCTAssertEqual(originalCity.id, deserializedCity.id)
        XCTAssertEqual(originalCity.name, deserializedCity.name)
        XCTAssertEqual(originalCity.coordinate.latitude, deserializedCity.coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(originalCity.coordinate.longitude, deserializedCity.coordinate.longitude, accuracy: 0.000001)
        XCTAssertEqual(originalCity.population, deserializedCity.population)
        XCTAssertEqual(originalCity.continent, deserializedCity.continent)
    }
    
    func testCLLocationCoordinate2DCompatibility() {
        let coordinate = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        let city = City(id: UUID(), name: "London", coordinate: coordinate, population: 8_982_000, continent: "Europe")
        
        XCTAssertEqual(city.clCoordinate.latitude, coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(city.clCoordinate.longitude, coordinate.longitude, accuracy: 0.000001)
    }

    func testInvalidJSON() {
        let invalidJSON = Data("This is not valid JSON".utf8)
        
        XCTAssertThrowsError(try City.deserialize(from: invalidJSON)) { error in
            XCTAssertTrue(error is DecodingError, "Expected DecodingError, but got \(type(of: error))")
        }
    }
    
    func testMissingFields() {
        let incompleteJSON = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "name": "Incomplete City"
        }
        """.data(using: .utf8)!
        
        XCTAssertThrowsError(try City.deserialize(from: incompleteJSON)) { error in
            XCTAssertTrue(error is DecodingError, "Expected DecodingError, but got \(type(of: error))")
        }
    }
    
    func testSerializeAndDeserializeWithSpecialCharacters() throws {
        let originalCity = City(id: UUID(), name: "São Paulo", coordinate: CLLocationCoordinate2D(latitude: -23.5505, longitude: -46.6333), population: 12_252_000, continent: "South America")
        
        let serializedData = try originalCity.serialize()
        let deserializedCity = try City.deserialize(from: serializedData)
        
        XCTAssertEqual(originalCity.name, deserializedCity.name)
    }
    
    func testSerializeAndDeserializeWithExtremeCordinates() throws {
        let originalCity = City(id: UUID(), name: "Extreme City", coordinate: CLLocationCoordinate2D(latitude: 90, longitude: 180), population: 1, continent: "Antarctica")
        
        let serializedData = try originalCity.serialize()
        let deserializedCity = try City.deserialize(from: serializedData)
        
        XCTAssertEqual(originalCity.coordinate.latitude, deserializedCity.coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(originalCity.coordinate.longitude, deserializedCity.coordinate.longitude, accuracy: 0.000001)
    }
}
