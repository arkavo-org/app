import AVFoundation
import Foundation
import Testing
@testable import ArkavoMediaKit

/// Tests that validate fMP4 content can be played by AVPlayer
@Suite("AVPlayer Playback Validation")
struct AVPlayerPlaybackTests {

    let testSPS = Data([0x67, 0x64, 0x00, 0x28, 0xAC, 0xD9, 0x40, 0x78,
                        0x02, 0x27, 0xE5, 0xC0, 0x44, 0x00, 0x00, 0x03,
                        0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0xF2, 0x3C])
    let testPPS = Data([0x68, 0xEE, 0x3C, 0x80])
    let testKeyID = Data(repeating: 0x12, count: 16)
    let testIV = Data([0xD5, 0xFB, 0xD6, 0xB8, 0x2E, 0xD9, 0x3E, 0x4E,
                       0xF9, 0x8A, 0xE4, 0x09, 0x31, 0xEE, 0x33, 0xB7])
    let testKey = Data(repeating: 0x3C, count: 16)

    // MARK: - Helper to create realistic video sample

    func createVideoSample(isIDR: Bool, size: Int) -> Data {
        var sample = Data()

        func appendNALLength(_ length: Int) {
            sample.append(UInt8((length >> 24) & 0xFF))
            sample.append(UInt8((length >> 16) & 0xFF))
            sample.append(UInt8((length >> 8) & 0xFF))
            sample.append(UInt8(length & 0xFF))
        }

        if isIDR {
            appendNALLength(testSPS.count)
            sample.append(testSPS)
            appendNALLength(testPPS.count)
            sample.append(testPPS)
            let sliceSize = max(size - sample.count - 4, 100)
            appendNALLength(sliceSize)
            sample.append(0x65)
            sample.append(Data(repeating: 0xAB, count: sliceSize - 1))
        } else {
            let sliceSize = max(size - 4, 50)
            appendNALLength(sliceSize)
            sample.append(0x41)
            sample.append(Data(repeating: 0xCD, count: sliceSize - 1))
        }

        return sample
    }

    // MARK: - Tests

    @Test("Generate unencrypted fMP4 and check AVAsset loads")
    func unencryptedAssetLoads() async throws {
        // Create unencrypted content
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [testSPS], pps: [testPPS]
        )
        // No encryption config = unencrypted
        let writer = FMP4Writer(tracks: [track], encryption: nil)

        let initSegment = writer.generateInitSegment()

        // Create a few unencrypted samples
        var samples: [FMP4Writer.Sample] = []
        for i in 0..<30 {
            let isIDR = (i == 0)
            let sampleData = createVideoSample(isIDR: isIDR, size: isIDR ? 10000 : 2000)
            samples.append(FMP4Writer.Sample(
                data: sampleData,
                duration: 3000,
                isSync: isIDR,
                subsamples: nil
            ))
        }

        let segment = writer.generateMediaSegment(trackID: 1, samples: samples, baseDecodeTime: 0)

        // Write to temp directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let initURL = tempDir.appendingPathComponent("init.mp4")
        let segmentURL = tempDir.appendingPathComponent("segment0.m4s")
        let playlistURL = tempDir.appendingPathComponent("playlist.m3u8")

        try initSegment.write(to: initURL)
        try segment.write(to: segmentURL)

        // Create simple unencrypted playlist
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-MAP:URI="init.mp4"
        #EXTINF:1.00000,
        segment0.m4s
        #EXT-X-ENDLIST
        """
        try playlist.write(to: playlistURL, atomically: true, encoding: .utf8)

        print("\n═══════════════════════════════════════════════════════")
        print("UNENCRYPTED PLAYBACK TEST")
        print("═══════════════════════════════════════════════════════")
        print("Temp dir: \(tempDir.path)")
        print("Init size: \(initSegment.count)")
        print("Segment size: \(segment.count)")

        // Try to load with AVURLAsset
        let asset = AVURLAsset(url: playlistURL)

        // Check if asset loads
        let status = try await asset.load(.isPlayable)
        print("Asset isPlayable: \(status)")

        // Try to load tracks
        let tracks = try await asset.load(.tracks)
        print("Track count: \(tracks.count)")

        for track in tracks {
            print("  Track: \(track.mediaType.rawValue)")
        }

        // Check for errors via player item
        let playerItem = AVPlayerItem(asset: asset)

        // Wait a moment for the player item to process
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        if let error = playerItem.error {
            print("❌ PlayerItem error: \(error)")
            Issue.record("AVPlayerItem failed: \(error)")
        } else {
            print("✓ No immediate player item error")
        }

        // Check status
        print("PlayerItem status: \(playerItem.status.rawValue)")

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)

        #expect(status == true, "Asset should be playable")
        #expect(tracks.count > 0, "Should have at least one track")
    }

    @Test("Validate moof structure with mp4dump equivalent")
    func validateMoofStructure() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [testSPS], pps: [testPPS]
        )
        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV)
        let writer = FMP4Writer(tracks: [track], encryption: encryption)
        let encryptor = CBCSEncryptor(key: testKey, iv: testIV)

        // Create samples
        var samples: [FMP4Writer.Sample] = []
        for i in 0..<10 {
            let isIDR = (i == 0)
            let sampleData = createVideoSample(isIDR: isIDR, size: isIDR ? 10000 : 2000)
            let result = encryptor.encryptVideoSample(sampleData, nalLengthSize: 4)
            samples.append(FMP4Writer.Sample(
                data: result.encryptedData,
                duration: 3000,
                isSync: isIDR,
                subsamples: result.subsamples
            ))
        }

        let segment = writer.generateMediaSegment(trackID: 1, samples: samples, baseDecodeTime: 0)

        print("\n═══════════════════════════════════════════════════════")
        print("MOOF STRUCTURE VALIDATION")
        print("═══════════════════════════════════════════════════════")
        print("Segment size: \(segment.count)")

        // Parse segment structure
        var offset = 0
        while offset + 8 <= segment.count {
            let sizeData = segment.subdata(in: offset..<(offset + 4))
            let size = Int(UInt32(bigEndian: sizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))
            let typeData = segment.subdata(in: (offset + 4)..<(offset + 8))
            let type = String(data: typeData, encoding: .ascii) ?? "????"

            print("[\(type)] offset=\(offset), size=\(size)")

            if type == "moof" {
                parseMoof(segment, at: offset, size: size)
            } else if type == "mdat" {
                print("  mdat payload size: \(size - 8)")
            }

            if size > 0 { offset += size } else { break }
        }
    }

    private func parseMoof(_ data: Data, at moofOffset: Int, size: Int) {
        var offset = moofOffset + 8
        let moofEnd = moofOffset + size

        while offset + 8 <= moofEnd {
            let boxSizeData = data.subdata(in: offset..<(offset + 4))
            let boxSize = Int(UInt32(bigEndian: boxSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))
            let boxTypeData = data.subdata(in: (offset + 4)..<(offset + 8))
            let boxType = String(data: boxTypeData, encoding: .ascii) ?? "????"

            print("  [\(boxType)] offset=\(offset - moofOffset) (abs: \(offset)), size=\(boxSize)")

            if boxType == "traf" {
                parseTraf(data, at: offset, size: boxSize, moofOffset: moofOffset)
            }

            if boxSize > 0 { offset += boxSize } else { break }
        }
    }

    private func parseTraf(_ data: Data, at trafOffset: Int, size: Int, moofOffset: Int) {
        var offset = trafOffset + 8
        let trafEnd = trafOffset + size

        while offset + 8 <= trafEnd {
            let boxSizeData = data.subdata(in: offset..<(offset + 4))
            let boxSize = Int(UInt32(bigEndian: boxSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))
            let boxTypeData = data.subdata(in: (offset + 4)..<(offset + 8))
            let boxType = String(data: boxTypeData, encoding: .ascii) ?? "????"

            let relOffset = offset - moofOffset
            print("    [\(boxType)] offset=\(relOffset) (abs: \(offset)), size=\(boxSize)")

            if boxType == "tfhd" {
                parseTfhd(data, at: offset)
            } else if boxType == "trun" {
                parseTrun(data, at: offset, moofOffset: moofOffset)
            } else if boxType == "senc" {
                print("      senc sample data at offset \(relOffset + 16) from moof")
            } else if boxType == "saio" {
                parseSaio(data, at: offset)
            }

            if boxSize > 0 { offset += boxSize } else { break }
        }
    }

    private func parseTfhd(_ data: Data, at offset: Int) {
        let flags = UInt32(data[offset + 9]) << 16 | UInt32(data[offset + 10]) << 8 | UInt32(data[offset + 11])
        let defaultBaseIsMoof = (flags & 0x020000) != 0
        print("      flags: 0x\(String(format: "%06X", flags)) (default-base-is-moof: \(defaultBaseIsMoof))")
    }

    private func parseTrun(_ data: Data, at offset: Int, moofOffset: Int) {
        let flags = UInt32(data[offset + 9]) << 16 | UInt32(data[offset + 10]) << 8 | UInt32(data[offset + 11])
        let hasDataOffset = (flags & 0x000001) != 0

        if hasDataOffset {
            let dataOffsetPos = offset + 16 // After sample_count
            let dataOffsetData = data.subdata(in: dataOffsetPos..<(dataOffsetPos + 4))
            let dataOffset = Int32(bigEndian: dataOffsetData.withUnsafeBytes { $0.load(as: Int32.self) })
            print("      data_offset: \(dataOffset) (points to moof+\(dataOffset))")

            // Validate: with default-base-is-moof, dataOffset is from moof start
            // So actual sample data position = moofOffset + dataOffset
            let sampleDataPos = moofOffset + Int(dataOffset)
            print("      -> sample data at absolute position: \(sampleDataPos)")
        }
    }

    private func parseSaio(_ data: Data, at offset: Int) {
        // saio: size(4) + type(4) + version/flags(4) + entry_count(4) + offset(4)
        let saioOffsetPos = offset + 16
        if saioOffsetPos + 4 <= data.count {
            let saioOffsetData = data.subdata(in: saioOffsetPos..<(saioOffsetPos + 4))
            let saioOffset = UInt32(bigEndian: saioOffsetData.withUnsafeBytes { $0.load(as: UInt32.self) })
            print("      saio offset: \(saioOffset) (points to senc data from moof)")
        }
    }

    @Test("Check trun sample entries match encrypted sample sizes")
    func trunSampleEntriesMatchSampleSizes() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [testSPS], pps: [testPPS]
        )
        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV)
        let writer = FMP4Writer(tracks: [track], encryption: encryption)
        let encryptor = CBCSEncryptor(key: testKey, iv: testIV)

        // Create samples and track sizes
        var samples: [FMP4Writer.Sample] = []
        var expectedSizes: [Int] = []

        for i in 0..<10 {
            let isIDR = (i == 0)
            let sampleData = createVideoSample(isIDR: isIDR, size: isIDR ? 10000 : 2000)
            let result = encryptor.encryptVideoSample(sampleData, nalLengthSize: 4)
            samples.append(FMP4Writer.Sample(
                data: result.encryptedData,
                duration: 3000,
                isSync: isIDR,
                subsamples: result.subsamples
            ))
            expectedSizes.append(result.encryptedData.count)
        }

        let segment = writer.generateMediaSegment(trackID: 1, samples: samples, baseDecodeTime: 0)

        print("\n═══════════════════════════════════════════════════════")
        print("TRUN SAMPLE SIZE VALIDATION")
        print("═══════════════════════════════════════════════════════")

        // Find trun and parse sample sizes
        let trunMarker = Data([0x74, 0x72, 0x75, 0x6E])
        guard let trunRange = segment.range(of: trunMarker) else {
            Issue.record("trun not found")
            return
        }

        let trunOffset = trunRange.lowerBound - 4
        let trunSizeData = segment.subdata(in: trunOffset..<(trunOffset + 4))
        let trunSize = Int(UInt32(bigEndian: trunSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))

        // Parse trun
        let flags = UInt32(segment[trunOffset + 9]) << 16 | UInt32(segment[trunOffset + 10]) << 8 | UInt32(segment[trunOffset + 11])
        let sampleCountData = segment.subdata(in: (trunOffset + 12)..<(trunOffset + 16))
        let sampleCount = Int(UInt32(bigEndian: sampleCountData.withUnsafeBytes { $0.load(as: UInt32.self) }))

        print("trun size: \(trunSize), flags: 0x\(String(format: "%06X", flags)), sample_count: \(sampleCount)")

        let hasDataOffset = (flags & 0x000001) != 0
        let hasSampleSize = (flags & 0x000200) != 0

        var entryOffset = trunOffset + 16
        if hasDataOffset { entryOffset += 4 }

        print("Expected samples: \(expectedSizes.count)")
        print("trun sample_count: \(sampleCount)")

        #expect(sampleCount == expectedSizes.count, "Sample count should match")

        if hasSampleSize {
            var totalTrunSize = 0
            for i in 0..<sampleCount {
                let sizeData = segment.subdata(in: entryOffset..<(entryOffset + 4))
                let size = Int(UInt32(bigEndian: sizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))
                totalTrunSize += size

                if i < expectedSizes.count {
                    let expected = expectedSizes[i]
                    let match = (size == expected) ? "✓" : "❌"
                    print("  [\(i)] trun size: \(size), expected: \(expected) \(match)")
                    #expect(size == expected, "Sample \(i) size mismatch: trun=\(size), actual=\(expected)")
                }
                entryOffset += 4
            }

            // Verify total size matches mdat payload
            let mdatMarker = Data([0x6D, 0x64, 0x61, 0x74])
            if let mdatRange = segment.range(of: mdatMarker) {
                let mdatOffset = mdatRange.lowerBound - 4
                let mdatSizeData = segment.subdata(in: mdatOffset..<(mdatOffset + 4))
                let mdatSize = Int(UInt32(bigEndian: mdatSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))
                let mdatPayload = mdatSize - 8

                print("\nTotal trun sizes: \(totalTrunSize)")
                print("mdat payload size: \(mdatPayload)")
                #expect(totalTrunSize == mdatPayload, "Total sample sizes should equal mdat payload")
            }
        }
    }
}
