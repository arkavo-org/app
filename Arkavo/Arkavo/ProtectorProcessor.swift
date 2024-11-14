import Compression
import CoreML
import CryptoKit
import Foundation

struct ContentSignature: Codable {
    let version: Int
    let embeddings: [Float16] // Semantic embeddings from BERT
    let ngrams: Set<String> // Efficient n-gram sets
    let keyphrases: [String] // Key phrases extracted
    let metadata: SignatureMetadata
    let checksum: String // For validation

    var compressedSize: Int {
        // Estimate compressed size for transmission
        embeddings.count * MemoryLayout<Float16>.size +
            ngrams.joined().utf8.count +
            keyphrases.joined().utf8.count +
            MemoryLayout<SignatureMetadata>.size
    }
}

struct SignatureMetadata: Codable {
    let createdAt: Date
    let sourceType: String
    let processingVersion: String
    let contentLength: Int
}

// MARK: - MacOS Preprocessing

class ContentPreprocessor {
    private let model: TextEmbedding
    private let tokenizer: BERTTokenizer
    private let batchSize = 32

    init() throws {
        model = try TextEmbedding(configuration: MLModelConfiguration())
        tokenizer = BERTTokenizer()
    }

    func generateSignature(for content: String) throws -> ContentSignature {
        // 1. Generate BERT embeddings
        let embeddings = try generateEmbeddings(for: content)

        // 2. Extract key phrases
        let keyphrases = extractKeyPhrases(from: content)

        // 3. Generate n-grams
        let ngrams = generateNgrams(from: content)

        // 4. Create metadata
        let metadata = SignatureMetadata(
            createdAt: Date(),
            sourceType: "text",
            processingVersion: "1.0",
            contentLength: content.count
        )

        // 5. Generate checksum
        let checksum = generateChecksum(embeddings: embeddings,
                                        ngrams: ngrams,
                                        keyphrases: keyphrases)

        return ContentSignature(
            version: 1,
            embeddings: embeddings,
            ngrams: ngrams,
            keyphrases: keyphrases,
            metadata: metadata,
            checksum: checksum
        )
    }

    func processBatch(_ posts: [RedditPost]) throws -> [ContentSignature] {
        // Create a dispatch group for parallel processing
        let group = DispatchGroup()
        var signatures: [Int: ContentSignature] = [:] // Use dictionary to maintain order
        var errors: [Error] = []

        let queue = DispatchQueue(label: "com.contentprocessor.batch",
                                  attributes: .concurrent)

        // Process each post in parallel
        for (index, post) in posts.enumerated() {
            group.enter()
            queue.async {
                do {
                    // FIXME: Combine title and content for processing
                    let combinedContent = [post.title, post.selftext]
                        .compactMap { $0 }
                        .joined(separator: " ")

                    // Generate signature
                    let signature = try self.generateSignature(for: combinedContent)

                    // Store result
                    queue.sync(flags: .barrier) {
                        signatures[index] = signature
                    }
                } catch {
                    queue.sync(flags: .barrier) {
                        errors.append(error)
                    }
                }
                group.leave()
            }
        }

        // Wait for all processing to complete
        group.wait()

        // If any errors occurred, throw the first one
        if let firstError = errors.first {
            throw firstError
        }

        // Return signatures in original order
        return signatures.sorted { $0.key < $1.key }.map(\.value)
    }

    func generateChecksum(embeddings: [Float16], ngrams: Set<String>, keyphrases: [String]) -> String {
        // Create a string that combines all the signature components
        var components: [String] = []

        // Add embeddings
        let embeddingString = embeddings
            .map { String(format: "%.4f", Float($0)) }
            .joined(separator: "")
        components.append(embeddingString)

        // Add sorted ngrams
        let ngramString = ngrams.sorted().joined(separator: "")
        components.append(ngramString)

        // Add sorted keyphrases
        let keyphraseString = keyphrases.sorted().joined(separator: "")
        components.append(keyphraseString)

        // Combine all components
        let combinedString = components.joined()

        // Generate SHA-256 hash using CryptoKit
        guard let data = combinedString.data(using: .utf8) else {
            return "" // Handle error appropriately in production
        }

        let hash = SHA256.hash(data: data)

        // Convert to hex string
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // Batch processing for Reddit data
    func batchProcessRedditPosts(_ posts: [RedditPost]) throws -> [ContentSignature] {
        try posts.chunked(into: batchSize).flatMap { batch in
            try processBatch(batch)
        }
    }

    private func generateEmbeddings(for content: String) throws -> [Float16] {
        // Tokenize input
        let tokens = tokenizer.tokenize(content)

        // Prepare input for the model
        let inputShape = [1, 512] as [NSNumber]
        let inputIds = try MLMultiArray(shape: inputShape, dataType: .int32)
        let attentionMask = try MLMultiArray(shape: inputShape, dataType: .int32)

        // Fill input arrays
        for (index, token) in tokens.prefix(512).enumerated() {
            inputIds[index] = NSNumber(value: token)
            attentionMask[index] = 1
        }

        // Get model prediction
        let input = TextEmbeddingInput(input_ids: inputIds, attention_mask: attentionMask)
        let output = try model.prediction(input: input)

        // Convert to Array of Float16
        return Array(UnsafeBufferPointer(start: output.var_547.dataPointer.assumingMemoryBound(to: Float16.self),
                                         count: output.var_547.count))
    }

    private func extractKeyPhrases(from content: String) -> [String] {
        // Implement key phrase extraction using NLP techniques
        // This is a simplified version - you might want to use more sophisticated methods
        let tagger = NSLinguisticTagger(tagSchemes: [.nameType, .lexicalClass], options: 0)
        tagger.string = content

        var phrases: [String] = []
        let options: NSLinguisticTagger.Options = [.omitWhitespace, .omitPunctuation]

        tagger.enumerateTags(in: NSRange(location: 0, length: content.utf16.count),
                             scheme: .nameType,
                             options: options)
        { tag, tokenRange, _, _ in
            if tag != nil {
                let phrase = (content as NSString).substring(with: tokenRange)
                phrases.append(phrase)
            }
//            print("tag = \(String(describing: tag)), tokenRange = \(tokenRange)")
        }

        return phrases
    }

    private func generateNgrams(from content: String) -> Set<String> {
        let words = content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty } // Filter out empty strings
        var ngrams = Set<String>()

        // Generate 1-3 grams, but only if we have enough words
        for n in 1 ... 3 {
            // Only process if we have enough words for this n-gram size
            if words.count >= n {
                for i in 0 ... (words.count - n) {
                    let ngram = words[i ..< (i + n)].joined(separator: " ")
                    ngrams.insert(ngram)
                }
            }
        }

        return ngrams
    }
}

// MARK: - iOS Detection

class ContentMatcher {
    private let similarityThreshold: Float = 0.85
    private let ngramMatchThreshold: Float = 0.3

    func findMatches(signature: ContentSignature, against candidates: [ContentSignature]) -> [Match] {
        // Quick rejection using n-grams
        let possibleMatches = candidates.filter { candidate in
            let ngramOverlap = calculateNgramOverlap(signature.ngrams, candidate.ngrams)
            return ngramOverlap >= ngramMatchThreshold
        }

        // Detailed matching for remaining candidates
        return possibleMatches.compactMap { candidate in
            let embeddingSimilarity = cosineSimilarity(signature.embeddings, candidate.embeddings)
            let phraseSimilarity = calculatePhraseSimilarity(signature.keyphrases, candidate.keyphrases)
            let ngramOverlap = signature.ngrams.intersection(candidate.ngrams).count

            // Calculate final similarity score
            let similarity = 0.6 * embeddingSimilarity +
                0.3 * phraseSimilarity +
                0.1 * Float(ngramOverlap) / Float(max(signature.ngrams.count, candidate.ngrams.count))

            guard similarity >= similarityThreshold else { return nil }

            let matchDetails = createMatchDetails(
                embeddingSimilarity: embeddingSimilarity,
                ngramOverlap: ngramOverlap,
                phraseSimilarity: phraseSimilarity
            )

            return Match(
                signature: candidate,
                similarity: similarity,
                matchType: determineMatchType(similarity),
                matchDetails: matchDetails
            )
        }
    }

    /// Determines the match type based on similarity scores
    func determineMatchType(_ similarity: Float) -> MatchType {
        MatchType.from(similarity: similarity)
    }

    /// Creates match details from similarity calculations
    func createMatchDetails(embeddingSimilarity: Float,
                            ngramOverlap: Int,
                            phraseSimilarity: Float) -> MatchDetails
    {
        MatchDetails(
            embeddingSimilarity: embeddingSimilarity,
            ngramMatches: ngramOverlap,
            phraseMatches: Int(phraseSimilarity * 100),
            metadata: [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "confidence": String(format: "%.2f", embeddingSimilarity),
            ]
        )
    }

    private func calculateNgramOverlap(_ set1: Set<String>, _ set2: Set<String>) -> Float {
        let intersection = set1.intersection(set2).count
        let union = set1.union(set2).count
        return Float(intersection) / Float(union)
    }

    private func calculateSimilarity(_ sig1: ContentSignature, _ sig2: ContentSignature) -> Float {
        // Combine multiple similarity metrics
        let embeddingSimilarity = cosineSimilarity(sig1.embeddings, sig2.embeddings)
        let phraseSimilarity = calculatePhraseSimilarity(sig1.keyphrases, sig2.keyphrases)

        // Weighted combination
        return 0.7 * embeddingSimilarity + 0.3 * phraseSimilarity
    }

    private func cosineSimilarity(_ v1: [Float16], _ v2: [Float16]) -> Float {
        // Implement cosine similarity
        var dotProduct: Float = 0
        var norm1: Float = 0
        var norm2: Float = 0

        for i in 0 ..< v1.count {
            dotProduct += Float(v1[i]) * Float(v2[i])
            norm1 += Float(v1[i]) * Float(v1[i])
            norm2 += Float(v2[i]) * Float(v2[i])
        }

        return dotProduct / (sqrt(norm1) * sqrt(norm2))
    }

    func calculatePhraseSimilarity(_ phrases1: [String], _ phrases2: [String]) -> Float {
        guard !phrases1.isEmpty, !phrases2.isEmpty else { return 0.0 }

        // Normalize phrases
        let normalizedPhrases1 = normalizePhrases(phrases1)
        let normalizedPhrases2 = normalizePhrases(phrases2)

        // Calculate exact matches
        let exactMatches = Set(normalizedPhrases1).intersection(Set(normalizedPhrases2))
        let exactMatchScore = Float(exactMatches.count) / Float(max(phrases1.count, phrases2.count))

        // Calculate fuzzy matches for non-exact matches
        var fuzzyMatchScore: Float = 0
        let remainingPhrases1 = normalizedPhrases1.filter { !exactMatches.contains($0) }
        let remainingPhrases2 = normalizedPhrases2.filter { !exactMatches.contains($0) }

        for phrase1 in remainingPhrases1 {
            var bestMatch: Float = 0
            for phrase2 in remainingPhrases2 {
                let similarity = calculateLevenshteinSimilarity(phrase1, phrase2)
                bestMatch = max(bestMatch, similarity)
            }
            fuzzyMatchScore += bestMatch
        }

        // Normalize fuzzy match score
        if !remainingPhrases1.isEmpty {
            fuzzyMatchScore /= Float(remainingPhrases1.count)
        }

        // Combine scores with weights
        let exactWeight: Float = 0.7
        let fuzzyWeight: Float = 0.3

        return exactWeight * exactMatchScore + fuzzyWeight * fuzzyMatchScore
    }

    private func normalizePhrases(_ phrases: [String]) -> [String] {
        phrases.map { phrase in
            phrase.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
        }
    }

    private func calculateLevenshteinSimilarity(_ s1: String, _ s2: String) -> Float {
        let empty = [Int](repeating: 0, count: s2.count + 1)
        var last = Array(0 ... s2.count)

        for (i, char1) in s1.enumerated() {
            var current = [i + 1] + empty

            for (j, char2) in s2.enumerated() {
                current[j + 1] = char1 == char2 ? last[j] :
                    min(last[j], min(last[j + 1], current[j])) + 1
            }

            last = current
        }

        let distance = Float(last.last ?? 0)
        let maxLength = Float(max(s1.count, s2.count))

        return 1.0 - (distance / maxLength)
    }
}

// MARK: - Utility Extensions

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

// MARK: - BERT Tokenizer

class BERTTokenizer {
    // Special tokens
    private let padToken = "[PAD]"
    private let unknownToken = "[UNK]"
    private let startToken = "[CLS]"
    private let endToken = "[SEP]"

    // Token mappings
    private let vocab: [String: Int32]
    private let maxTokens = 512

    init() {
        // Initialize with basic BERT vocabulary
        // In practice, you would load this from a vocabulary file
        vocab = BERTTokenizer.loadVocabulary()
    }

    func tokenize(_ text: String) -> [Int32] {
        // 1. Preprocess text
        let cleanedText = preprocess(text)

        // 2. Split into words and subwords
        let wordPieces = cleanedText
            .components(separatedBy: .whitespacesAndNewlines)
            .flatMap { wordToWordPieces($0) }

        // 3. Convert to token IDs with special tokens
        var tokens: [Int32] = [getTokenId(startToken)]
        tokens += wordPieces.map { getTokenId($0) }
        tokens.append(getTokenId(endToken))

        // 4. Pad or truncate to maxTokens
        return padTokens(tokens)
    }

    private func preprocess(_ text: String) -> String {
        // Basic text preprocessing
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-zA-Z0-9\\s]", with: " ", options: .regularExpression)
    }

    private func wordToWordPieces(_ word: String) -> [String] {
        var pieces: [String] = []
        var start = 0

        while start < word.count {
            var end = word.count
            var found = false

            while start < end {
                let piece = String(word[word.index(word.startIndex, offsetBy: start) ..< word.index(word.startIndex, offsetBy: end)])
                let prefixedPiece = start == 0 ? piece : "##" + piece

                if vocab[prefixedPiece] != nil {
                    pieces.append(prefixedPiece)
                    found = true
                    break
                }
                end -= 1
            }

            if !found {
                pieces.append(unknownToken)
                break
            }
            start = end
        }

        return pieces
    }

    private func getTokenId(_ token: String) -> Int32 {
        vocab[token] ?? vocab[unknownToken]!
    }

    private func padTokens(_ tokens: [Int32]) -> [Int32] {
        var result = tokens

        // Truncate if necessary
        if result.count > maxTokens {
            result = Array(result.prefix(maxTokens - 1))
            result.append(getTokenId(endToken))
        }
        // Pad if necessary
        else if result.count < maxTokens {
            result += Array(repeating: getTokenId(padToken), count: maxTokens - result.count)
        }

        return result
    }

    // MARK: - Vocabulary Loading

    private static func loadVocabulary() -> [String: Int32] {
        // This is a minimal vocabulary for demonstration
        // In practice, you would load this from a file
        var vocab: [String: Int32] = [
            "[PAD]": 0,
            "[UNK]": 1,
            "[CLS]": 2,
            "[SEP]": 3,
            "the": 4,
            "##s": 5,
            "##ing": 6,
            "a": 7,
            "an": 8,
            "and": 9,
            "to": 10,
            "in": 11,
            "for": 12,
            "of": 13,
            "on": 14,
            "at": 15,
            // Add more vocabulary items as needed
        ]

        // Add basic alphabet
        for char in "abcdefghijklmnopqrstuvwxyz" {
            if vocab[String(char)] == nil {
                vocab[String(char)] = Int32(vocab.count)
            }
        }

        return vocab
    }
}

// MARK: - Vocabulary Loading Extension

extension BERTTokenizer {
    // Load vocabulary from a file
    static func loadFromFile(_: URL) throws -> BERTTokenizer {
        let tokenizer = BERTTokenizer()
        // Implement vocabulary loading from file
        return tokenizer
    }

    // Load vocabulary from a bundled resource
    static func loadFromBundle() throws -> BERTTokenizer {
        guard let url = Bundle.main.url(forResource: "bert-vocab", withExtension: "txt") else {
            throw TokenizerError.vocabularyNotFound
        }
        return try loadFromFile(url)
    }
}

// MARK: - Error Types

enum TokenizerError: Error {
    case vocabularyNotFound
    case invalidVocabularyFormat
    case tokenizationError
}

// MARK: - Match Types

struct Match: Codable {
    /// The matching signature that was found
    let signature: ContentSignature

    /// Similarity score between 0 and 1
    let similarity: Float

    /// Type of match that was found
    let matchType: MatchType

    /// Detailed breakdown of why this was considered a match
    let matchDetails: MatchDetails

    /// Timestamp when the match was found
    let timestamp: Date

    init(signature: ContentSignature,
         similarity: Float,
         matchType: MatchType,
         matchDetails: MatchDetails = .init())
    {
        self.signature = signature
        self.similarity = similarity
        self.matchType = matchType
        self.matchDetails = matchDetails
        timestamp = Date()
    }
}

// MARK: - Match Details

struct MatchDetails: Codable {
    /// Similarity score from embeddings comparison
    let embeddingSimilarity: Float?

    /// Number of matching n-grams
    let ngramMatches: Int?

    /// Number of matching key phrases
    let phraseMatches: Int?

    /// Additional metadata about the match
    let metadata: [String: String]

    init(embeddingSimilarity: Float? = nil,
         ngramMatches: Int? = nil,
         phraseMatches: Int? = nil,
         metadata: [String: String] = [:])
    {
        self.embeddingSimilarity = embeddingSimilarity
        self.ngramMatches = ngramMatches
        self.phraseMatches = phraseMatches
        self.metadata = metadata
    }
}

// MARK: - Match Type

enum MatchType: String, Codable {
    /// Exact or near-exact match (similarity > 0.95)
    case exact

    /// High similarity but not exact (similarity > 0.85)
    case similar

    /// Moderate similarity (similarity > 0.70)
    case partial

    /// Low similarity but above threshold
    case weak

    /// Factory method to determine match type from similarity score
    static func from(similarity: Float) -> MatchType {
        switch similarity {
        case 0.95 ... 1.0:
            .exact
        case 0.85 ..< 0.95:
            .similar
        case 0.70 ..< 0.85:
            .partial
        default:
            .weak
        }
    }
}

// MARK: - Compression Extensions

enum CompressionError: Error {
    case compressionFailed
    case decompressionFailed
    case encodingFailed
    case decodingFailed
    case invalidPointer
}

// MARK: - Compression Extensions

extension ContentSignature {
    /// Compress the signature for efficient transmission
    func compressed() throws -> Data {
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(self)
        return try jsonData.compressed()
    }

    /// Decompress data back into a signature
    static func decompress(_ data: Data) throws -> ContentSignature {
        let jsonData = try data.decompressed()
        let decoder = JSONDecoder()
        return try decoder.decode(ContentSignature.self, from: jsonData)
    }
}
