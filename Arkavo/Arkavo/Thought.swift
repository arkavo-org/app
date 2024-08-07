import Foundation

struct Thought: Codable {
    let content: [MediaContent]

    init(content: [MediaContent]) {
        self.content = content
    }

    // Helper method for creating a simple text Thought
    static func createTextThought(_ text: String) -> Thought {
        let textContent = MediaContent(type: .text, content: text)
        return Thought(content: [textContent])
    }

    // PropertyList encoding/decoding
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    private static let decoder = PropertyListDecoder()

    func serialize() throws -> Data {
        try Thought.encoder.encode(self)
    }

    static func deserialize(from data: Data) throws -> Thought {
        try decoder.decode(Thought.self, from: data)
    }
}

enum MediaType: String, Codable {
    case text
    case image
    case audio
    case video
    // Add more media types as needed
}

struct MediaContent: Codable {
    let type: MediaType
    let content: String // URL or text content
}
