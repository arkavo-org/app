//
//  RecordingProtectionServiceTests.swift
//  ArkavoCreatorTests
//
//  Unit tests for TDF3 content protection service
//

@testable import ArkavoCreator
import XCTest

final class RecordingProtectionServiceTests: XCTestCase {

    // MARK: - KAS Endpoint Tests

    /// Test that KAS endpoint is reachable and returns valid response
    /// This would have caught the `publicKey` vs `public_key` bug
    func testKASEndpointReturnsValidPublicKey() async throws {
        let kasURL = URL(string: "https://100.arkavo.net")!
        var components = URLComponents(url: kasURL, resolvingAgainstBaseURL: true)!
        components.path = "/kas/v2/kas_public_key"
        components.queryItems = [URLQueryItem(name: "algorithm", value: "rsa")]

        guard let url = components.url else {
            XCTFail("Failed to construct KAS URL")
            return
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        // Verify HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Response is not HTTP response")
            return
        }
        XCTAssertEqual(httpResponse.statusCode, 200, "KAS should return 200 OK")

        // Verify JSON structure
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("KAS response is not valid JSON")
            return
        }

        // CRITICAL: Test the actual field name used by the server
        // This test would have caught the `publicKey` vs `public_key` bug
        XCTAssertNotNil(json["public_key"], "KAS response must contain 'public_key' field (snake_case)")
        XCTAssertNil(json["publicKey"], "KAS uses snake_case, not camelCase")

        // Verify it's a valid PEM
        guard let publicKey = json["public_key"] as? String else {
            XCTFail("public_key is not a string")
            return
        }
        XCTAssertTrue(publicKey.contains("-----BEGIN PUBLIC KEY-----"), "Should be valid PEM format")
        XCTAssertTrue(publicKey.contains("-----END PUBLIC KEY-----"), "Should be valid PEM format")
    }

    /// Test full protection flow creates valid TDF archive
    func testProtectVideoCreatesValidTDFArchive() async throws {
        let kasURL = URL(string: "https://100.arkavo.net")!
        let service = RecordingProtectionService(kasURL: kasURL)

        // Create small test video data (just random bytes for testing)
        let testData = Data(repeating: 0x42, count: 1024)
        let assetID = UUID().uuidString

        // This should not throw - if it does, the test fails
        let tdfArchive = try await service.protectVideo(videoData: testData, assetID: assetID)

        // Verify we got data back
        XCTAssertGreaterThan(tdfArchive.count, 0, "TDF archive should not be empty")

        // Verify it's a valid ZIP (starts with PK signature)
        let zipSignature = Data([0x50, 0x4B, 0x03, 0x04])
        XCTAssertEqual(tdfArchive.prefix(4), zipSignature, "TDF should be a valid ZIP archive")

        // Write to temp file and extract to verify contents
        let tempTDF = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).tdf")
        try tdfArchive.write(to: tempTDF)
        defer { try? FileManager.default.removeItem(at: tempTDF) }

        // Extract and verify manifest
        let manifest = try TDFArchiveReader.extractManifest(from: tempTDF)

        // Verify manifest structure
        XCTAssertNotNil(manifest["encryptionInformation"], "Manifest must have encryptionInformation")
        XCTAssertNotNil(manifest["payload"], "Manifest must have payload")
        XCTAssertNotNil(manifest["meta"], "Manifest must have meta")

        // Verify encryption info
        guard let encInfo = manifest["encryptionInformation"] as? [String: Any] else {
            XCTFail("encryptionInformation is not a dictionary")
            return
        }

        guard let method = encInfo["method"] as? [String: Any] else {
            XCTFail("method is not a dictionary")
            return
        }
        XCTAssertEqual(method["algorithm"] as? String, "AES-128-CBC", "Should use AES-128-CBC")
        XCTAssertNotNil(method["iv"], "Must have IV")

        // Verify key access
        guard let keyAccess = encInfo["keyAccess"] as? [[String: Any]],
              let firstKey = keyAccess.first else {
            XCTFail("keyAccess is missing or empty")
            return
        }
        XCTAssertEqual(firstKey["type"] as? String, "wrapped", "Key type should be wrapped")
        XCTAssertNotNil(firstKey["wrappedKey"], "Must have wrapped key")
        XCTAssertEqual(firstKey["url"] as? String, kasURL.absoluteString, "KAS URL should match")

        // Verify meta
        guard let meta = manifest["meta"] as? [String: Any] else {
            XCTFail("meta is not a dictionary")
            return
        }
        XCTAssertEqual(meta["assetId"] as? String, assetID, "Asset ID should match")
        XCTAssertNotNil(meta["protectedAt"], "Must have protectedAt timestamp")
    }

    /// Test that TDFArchiveReader correctly extracts manifest
    func testTDFArchiveReaderExtractsManifest() async throws {
        let kasURL = URL(string: "https://100.arkavo.net")!
        let service = RecordingProtectionService(kasURL: kasURL)

        let testData = Data(repeating: 0x42, count: 512)
        let tdfArchive = try await service.protectVideo(videoData: testData, assetID: "test-asset")

        let tempTDF = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).tdf")
        try tdfArchive.write(to: tempTDF)
        defer { try? FileManager.default.removeItem(at: tempTDF) }

        // This should not throw
        let manifest = try TDFArchiveReader.extractManifest(from: tempTDF)

        XCTAssertFalse(manifest.isEmpty, "Manifest should not be empty")
    }

    /// Test invalid TDF archive throws appropriate error
    func testInvalidTDFArchiveThrowsError() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).tdf")

        // Write invalid data (not a ZIP)
        try Data("not a zip file".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            _ = try TDFArchiveReader.extractManifest(from: tempFile)
            XCTFail("Should have thrown error for invalid TDF")
        } catch {
            // Expected - verify it's the right error type
            XCTAssertTrue(error is RecordingProtectionError, "Should throw RecordingProtectionError")
        }
    }

    // MARK: - Error Handling Tests

    /// Test that protection fails gracefully with invalid KAS URL
    func testProtectionFailsWithInvalidKASURL() async {
        let invalidKASURL = URL(string: "https://invalid.example.com")!
        let service = RecordingProtectionService(kasURL: invalidKASURL)

        let testData = Data(repeating: 0x42, count: 256)

        do {
            _ = try await service.protectVideo(videoData: testData, assetID: "test")
            XCTFail("Should have thrown error for invalid KAS URL")
        } catch {
            // Expected - protection should fail
            print("Expected error: \(error)")
        }
    }
}

// MARK: - Integration Tests

final class TDFProtectionIntegrationTests: XCTestCase {

    /// Full end-to-end test: protect video, verify TDF, extract manifest
    func testEndToEndProtectionFlow() async throws {
        let kasURL = URL(string: "https://100.arkavo.net")!
        let service = RecordingProtectionService(kasURL: kasURL)

        // Simulate a small video file
        let videoData = Data(repeating: 0xFF, count: 4096)
        let assetID = "integration-test-\(UUID().uuidString)"

        // Step 1: Protect the video
        let tdfArchive = try await service.protectVideo(videoData: videoData, assetID: assetID)
        print("✅ Created TDF archive: \(tdfArchive.count) bytes")

        // Step 2: Save to file
        let tempTDF = FileManager.default.temporaryDirectory.appendingPathComponent("\(assetID).tdf")
        try tdfArchive.write(to: tempTDF)
        defer { try? FileManager.default.removeItem(at: tempTDF) }
        print("✅ Saved TDF to: \(tempTDF.path)")

        // Step 3: Verify file exists and has content
        let attrs = try FileManager.default.attributesOfItem(atPath: tempTDF.path)
        let fileSize = attrs[.size] as? Int64 ?? 0
        XCTAssertGreaterThan(fileSize, 0, "TDF file should have content")
        print("✅ TDF file size: \(fileSize) bytes")

        // Step 4: Extract and verify manifest
        let manifest = try TDFArchiveReader.extractManifest(from: tempTDF)
        print("✅ Extracted manifest with \(manifest.count) keys")

        // Step 5: Verify all required fields
        XCTAssertNotNil(manifest["encryptionInformation"])
        XCTAssertNotNil(manifest["payload"])
        XCTAssertNotNil(manifest["meta"])

        let meta = manifest["meta"] as? [String: Any]
        XCTAssertEqual(meta?["assetId"] as? String, assetID)
        print("✅ Asset ID verified: \(assetID)")

        print("🎉 End-to-end protection test passed!")
    }
}
