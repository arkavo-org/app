import Foundation
import Testing
@testable import ArkavoMediaKit

// MARK: - FairPlay Diagnostic Tests

/// Comprehensive automated diagnostic tests for FairPlay/fMP4 playback.
/// These tests validate the entire pipeline from content generation to playback readiness.
@Suite("FairPlay Playback Diagnostics")
struct FairPlayDiagnosticTests {

    // MARK: - Test Fixtures

    let testKey = Data(repeating: 0x3C, count: 16)
    let testIV = Data([0xD5, 0xFB, 0xD6, 0xB8, 0x2E, 0xD9, 0x3E, 0x4E,
                       0xF9, 0x8A, 0xE4, 0x09, 0x31, 0xEE, 0x33, 0xB7])
    let testKeyID = Data(repeating: 0x12, count: 16)

    // Sample H.264 SPS/PPS
    let sampleSPS = Data([0x67, 0x64, 0x00, 0x28, 0xAC, 0xD9, 0x40, 0x78,
                          0x02, 0x27, 0xE5, 0xC0, 0x44, 0x00, 0x00, 0x03,
                          0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0xF2, 0x3C,
                          0x60, 0xC6, 0x58])
    let samplePPS = Data([0x68, 0xEE, 0x3C, 0x80])

    // MARK: - Box Parsing Helpers

    private func parseBoxHeader(_ data: Data, at offset: Int) -> (size: Int, type: String, headerSize: Int)? {
        guard offset + 8 <= data.count else { return nil }
        let sizeData = data.subdata(in: offset..<(offset + 4))
        let size = Int(UInt32(bigEndian: sizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))
        let typeData = data.subdata(in: (offset + 4)..<(offset + 8))
        guard let type = String(data: typeData, encoding: .ascii) else { return nil }
        if size == 1 && offset + 16 <= data.count {
            let extSizeData = data.subdata(in: (offset + 8)..<(offset + 16))
            let extSize = Int(UInt64(bigEndian: extSizeData.withUnsafeBytes { $0.load(as: UInt64.self) }))
            return (extSize, type, 16)
        }
        return (size, type, 8)
    }

    private func findBoxRecursive(_ data: Data, type: String, startingAt start: Int = 0, endAt end: Int? = nil) -> (offset: Int, size: Int)? {
        let endOffset = end ?? data.count
        var offset = start
        while offset + 8 <= endOffset {
            guard let header = parseBoxHeader(data, at: offset) else { break }
            if header.type == type { return (offset, header.size) }

            let containerTypes = ["moov", "moof", "trak", "mdia", "minf", "stbl", "traf", "mvex", "edts", "dinf", "sinf", "schi"]
            if containerTypes.contains(header.type) {
                let boxEnd = min(offset + header.size, endOffset)
                if let found = findBoxRecursive(data, type: type, startingAt: offset + header.headerSize, endAt: boxEnd) {
                    return found
                }
            } else if header.type == "stsd" {
                // stsd has: header(8) + version/flags(4) + entry_count(4), then sample entries
                let entryCountOffset = offset + 8 + 4
                if entryCountOffset + 4 <= endOffset {
                    let entryCountData = data.subdata(in: entryCountOffset..<(entryCountOffset + 4))
                    let entryCount = UInt32(bigEndian: entryCountData.withUnsafeBytes { $0.load(as: UInt32.self) })
                    var entryOffset = entryCountOffset + 4
                    let stsdEnd = min(offset + header.size, endOffset)

                    for _ in 0..<entryCount {
                        if entryOffset + 8 > stsdEnd { break }
                        guard let entryHeader = parseBoxHeader(data, at: entryOffset) else { break }

                        // Sample entries (avc1, encv, hvc1, etc.) contain nested boxes after fixed header
                        // Video sample entry: 8 (header) + 78 (payload) = 86 bytes before nested boxes
                        // Audio sample entry: 8 (header) + 28 (payload) = 36 bytes before nested boxes
                        let sampleEntryTypes = ["avc1", "encv", "hvc1", "hev1", "mp4a", "enca"]
                        if sampleEntryTypes.contains(entryHeader.type) {
                            let isVideo = ["avc1", "encv", "hvc1", "hev1"].contains(entryHeader.type)
                            let fixedHeaderSize = isVideo ? 86 : 36 // Video vs audio sample entry (header + payload)
                            let nestedStart = entryOffset + fixedHeaderSize
                            let entryEnd = min(entryOffset + entryHeader.size, stsdEnd)

                            if nestedStart < entryEnd {
                                if let found = findBoxRecursive(data, type: type, startingAt: nestedStart, endAt: entryEnd) {
                                    return found
                                }
                            }
                        }

                        if entryHeader.size > 0 { entryOffset += entryHeader.size } else { break }
                    }
                }
            }
            if header.size > 0 { offset += header.size } else { break }
        }
        return nil
    }

    private func getAllBoxTypes(_ data: Data, startingAt start: Int = 0, indent: String = "") -> [String] {
        var types: [String] = []
        var offset = start
        while offset + 8 <= data.count {
            guard let header = parseBoxHeader(data, at: offset) else { break }
            types.append("\(indent)\(header.type) (size: \(header.size), offset: \(offset))")
            let containerTypes = ["moov", "moof", "trak", "mdia", "minf", "stbl", "traf", "mvex", "edts", "dinf", "sinf", "schi", "stsd"]
            if containerTypes.contains(header.type) {
                let children = getAllBoxTypes(data, startingAt: offset + 8, indent: indent + "  ")
                for child in children {
                    if child.hasPrefix(indent + "  ") || offset + header.size > data.count { break }
                    types.append(child)
                }
            }
            if header.size > 0 { offset += header.size } else { break }
        }
        return types
    }

    // MARK: - 1. Init Segment Structure Tests

    @Test("Init segment has required top-level boxes: ftyp, moov")
    func initSegmentTopLevelBoxes() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track])
        let initSegment = writer.generateInitSegment()

        // Parse top-level boxes
        var offset = 0
        var topLevelTypes: [String] = []
        while offset + 8 <= initSegment.count {
            guard let header = parseBoxHeader(initSegment, at: offset) else { break }
            topLevelTypes.append(header.type)
            offset += header.size
        }

        #expect(topLevelTypes.contains("ftyp"), "Missing ftyp box")
        #expect(topLevelTypes.contains("moov"), "Missing moov box")
        #expect(topLevelTypes[0] == "ftyp", "ftyp must be first box")
        print("✅ Init segment top-level boxes: \(topLevelTypes)")
    }

    @Test("Init segment moov has required children: mvhd, trak, mvex")
    func initSegmentMoovChildren() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track])
        let initSegment = writer.generateInitSegment()

        #expect(findBoxRecursive(initSegment, type: "mvhd") != nil, "Missing mvhd in moov")
        #expect(findBoxRecursive(initSegment, type: "trak") != nil, "Missing trak in moov")
        #expect(findBoxRecursive(initSegment, type: "mvex") != nil, "Missing mvex in moov (required for fragmented)")
        print("✅ moov contains required children: mvhd, trak, mvex")
    }

    @Test("Init segment trak has required hierarchy: tkhd, edts, mdia")
    func initSegmentTrakHierarchy() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track])
        let initSegment = writer.generateInitSegment()

        #expect(findBoxRecursive(initSegment, type: "tkhd") != nil, "Missing tkhd in trak")
        #expect(findBoxRecursive(initSegment, type: "edts") != nil, "Missing edts in trak (Apple HLS requirement)")
        #expect(findBoxRecursive(initSegment, type: "mdia") != nil, "Missing mdia in trak")
        #expect(findBoxRecursive(initSegment, type: "mdhd") != nil, "Missing mdhd in mdia")
        #expect(findBoxRecursive(initSegment, type: "hdlr") != nil, "Missing hdlr in mdia")
        #expect(findBoxRecursive(initSegment, type: "minf") != nil, "Missing minf in mdia")
        print("✅ trak hierarchy complete: tkhd, edts, mdia (mdhd, hdlr, minf)")
    }

    @Test("Init segment stbl has required sample table boxes")
    func initSegmentStblBoxes() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track])
        let initSegment = writer.generateInitSegment()

        #expect(findBoxRecursive(initSegment, type: "stbl") != nil, "Missing stbl in minf")
        #expect(findBoxRecursive(initSegment, type: "stsd") != nil, "Missing stsd in stbl")
        #expect(findBoxRecursive(initSegment, type: "stts") != nil, "Missing stts in stbl")
        #expect(findBoxRecursive(initSegment, type: "stsc") != nil, "Missing stsc in stbl")
        #expect(findBoxRecursive(initSegment, type: "stsz") != nil, "Missing stsz in stbl")
        #expect(findBoxRecursive(initSegment, type: "stco") != nil, "Missing stco in stbl")
        print("✅ stbl contains all required boxes: stsd, stts, stsc, stsz, stco")
    }

    // MARK: - 2. Encrypted Init Segment Tests

    @Test("Encrypted init has encv sample entry (not avc1)")
    func encryptedInitHasEncv() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV)
        let writer = FMP4Writer(tracks: [track], encryption: encryption)
        let initSegment = writer.generateInitSegment()

        let encvMarker = Data([0x65, 0x6E, 0x63, 0x76]) // "encv"
        let avc1Marker = Data([0x61, 0x76, 0x63, 0x31]) // "avc1"
        let frmaMarker = Data([0x66, 0x72, 0x6D, 0x61]) // "frma"

        #expect(initSegment.range(of: encvMarker) != nil, "Encrypted content must have encv sample entry")

        // avc1 SHOULD appear inside frma box (original format indicator), not as a sample entry
        // Check that if avc1 is present, it's after frma (meaning it's inside the frma box)
        if let avc1Range = initSegment.range(of: avc1Marker),
           let frmaRange = initSegment.range(of: frmaMarker) {
            // avc1 should be inside frma (within ~4-8 bytes after frma type)
            let expectedAvc1Start = frmaRange.upperBound
            let isInsideFrma = avc1Range.lowerBound >= expectedAvc1Start && avc1Range.lowerBound <= expectedAvc1Start + 4
            #expect(isInsideFrma, "avc1 should only appear inside frma box, not as sample entry")
        }
        print("✅ Encrypted init uses encv sample entry (avc1 only in frma as original format)")
    }

    @Test("Encrypted init has sinf with frma, schm, schi/tenc")
    func encryptedInitHasSinf() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV)
        let writer = FMP4Writer(tracks: [track], encryption: encryption)
        let initSegment = writer.generateInitSegment()

        #expect(findBoxRecursive(initSegment, type: "sinf") != nil, "Missing sinf in encv")
        #expect(findBoxRecursive(initSegment, type: "frma") != nil, "Missing frma in sinf (original format)")
        #expect(findBoxRecursive(initSegment, type: "schm") != nil, "Missing schm in sinf (scheme type)")
        #expect(findBoxRecursive(initSegment, type: "schi") != nil, "Missing schi in sinf (scheme info)")
        #expect(findBoxRecursive(initSegment, type: "tenc") != nil, "Missing tenc in schi (track encryption)")
        print("✅ sinf hierarchy complete: frma, schm, schi/tenc")
    }

    @Test("Encrypted init has pssh box with FairPlay system ID")
    func encryptedInitHasPssh() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV)
        let writer = FMP4Writer(tracks: [track], encryption: encryption)
        let initSegment = writer.generateInitSegment()

        guard let psshInfo = findBoxRecursive(initSegment, type: "pssh") else {
            Issue.record("Missing pssh box in encrypted init segment")
            return
        }

        // FairPlay system ID: 94CE86FB-07FF-4F43-ADB8-93D2FA968CA2
        let fairPlaySystemID = Data([0x94, 0xCE, 0x86, 0xFB, 0x07, 0xFF, 0x4F, 0x43,
                                      0xAD, 0xB8, 0x93, 0xD2, 0xFA, 0x96, 0x8C, 0xA2])

        // System ID is at offset 12 (size + type + version/flags)
        let systemIDOffset = psshInfo.offset + 12
        guard systemIDOffset + 16 <= initSegment.count else {
            Issue.record("pssh box too small for system ID")
            return
        }

        let actualSystemID = initSegment.subdata(in: systemIDOffset..<(systemIDOffset + 16))
        #expect(actualSystemID == fairPlaySystemID, "pssh must have FairPlay system ID")
        print("✅ pssh box contains FairPlay system ID")
    }

    @Test("tenc box has correct CBCS pattern (1:9)")
    func tencHasCorrectPattern() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV, cryptByteBlock: 1, skipByteBlock: 9)
        let writer = FMP4Writer(tracks: [track], encryption: encryption)
        let initSegment = writer.generateInitSegment()

        guard let tencInfo = findBoxRecursive(initSegment, type: "tenc") else {
            Issue.record("Missing tenc box")
            return
        }

        // tenc structure: size(4) + type(4) + version(1) + flags(3) + reserved(1) + pattern(1) + ...
        // Pattern byte at offset 13: (crypt << 4) | skip = (1 << 4) | 9 = 0x19
        let patternOffset = tencInfo.offset + 13
        guard patternOffset < initSegment.count else {
            Issue.record("tenc too small for pattern byte")
            return
        }

        let patternByte = initSegment[patternOffset]
        let cryptBlocks = (patternByte >> 4) & 0x0F
        let skipBlocks = patternByte & 0x0F

        #expect(cryptBlocks == 1, "CBCS crypt_byte_block should be 1, got \(cryptBlocks)")
        #expect(skipBlocks == 9, "CBCS skip_byte_block should be 9, got \(skipBlocks)")
        print("✅ tenc has correct CBCS pattern: crypt=\(cryptBlocks), skip=\(skipBlocks)")
    }

    // MARK: - 3. Media Segment Structure Tests

    @Test("Media segment has required top-level boxes: styp, moof, mdat")
    func mediaSegmentTopLevelBoxes() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track])
        let samples = [FMP4Writer.Sample(data: Data(repeating: 0xAA, count: 100), duration: 3000, isSync: true)]
        let mediaSegment = writer.generateMediaSegment(trackID: 1, samples: samples, baseDecodeTime: 0)

        var offset = 0
        var topLevelTypes: [String] = []
        while offset + 8 <= mediaSegment.count {
            guard let header = parseBoxHeader(mediaSegment, at: offset) else { break }
            topLevelTypes.append(header.type)
            offset += header.size
        }

        #expect(topLevelTypes.contains("styp"), "Missing styp box")
        #expect(topLevelTypes.contains("moof"), "Missing moof box")
        #expect(topLevelTypes.contains("mdat"), "Missing mdat box")
        #expect(topLevelTypes[0] == "styp", "styp must be first box in media segment")
        print("✅ Media segment top-level boxes: \(topLevelTypes)")
    }

    @Test("Media segment moof has mfhd and traf")
    func mediaSegmentMoofChildren() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track])
        let samples = [FMP4Writer.Sample(data: Data(repeating: 0xAA, count: 100), duration: 3000, isSync: true)]
        let mediaSegment = writer.generateMediaSegment(trackID: 1, samples: samples, baseDecodeTime: 0)

        #expect(findBoxRecursive(mediaSegment, type: "mfhd") != nil, "Missing mfhd in moof")
        #expect(findBoxRecursive(mediaSegment, type: "traf") != nil, "Missing traf in moof")
        print("✅ moof contains: mfhd, traf")
    }

    @Test("Media segment traf has tfhd, tfdt, trun in correct order")
    func mediaSegmentTrafOrder() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track])
        let samples = [FMP4Writer.Sample(data: Data(repeating: 0xAA, count: 100), duration: 3000, isSync: true)]
        let mediaSegment = writer.generateMediaSegment(trackID: 1, samples: samples, baseDecodeTime: 0)

        guard let moofInfo = findBoxRecursive(mediaSegment, type: "moof"),
              let trafInfo = findBoxRecursive(mediaSegment, type: "traf", startingAt: moofInfo.offset + 8) else {
            Issue.record("Missing moof or traf")
            return
        }

        // Get traf children in order
        var childTypes: [String] = []
        var offset = trafInfo.offset + 8
        let endOffset = trafInfo.offset + trafInfo.size
        while offset + 8 <= endOffset {
            guard let header = parseBoxHeader(mediaSegment, at: offset) else { break }
            childTypes.append(header.type)
            offset += header.size
        }

        #expect(childTypes.count >= 3, "traf should have at least 3 children")
        #expect(childTypes[0] == "tfhd", "First box in traf must be tfhd")
        #expect(childTypes[1] == "tfdt", "Second box in traf must be tfdt")
        #expect(childTypes[2] == "trun", "Third box in traf must be trun")
        print("✅ traf box order: \(childTypes)")
    }

    // MARK: - 4. Encrypted Media Segment Tests

    @Test("Encrypted media segment has senc, saiz, saio in traf")
    func encryptedMediaSegmentHasEncryptionBoxes() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV)
        let writer = FMP4Writer(tracks: [track], encryption: encryption)
        let samples = [FMP4Writer.Sample(data: Data(repeating: 0xAA, count: 100), duration: 3000, isSync: true)]
        let mediaSegment = writer.generateMediaSegment(trackID: 1, samples: samples, baseDecodeTime: 0)

        #expect(findBoxRecursive(mediaSegment, type: "senc") != nil, "Missing senc in encrypted traf")
        #expect(findBoxRecursive(mediaSegment, type: "saiz") != nil, "Missing saiz in encrypted traf")
        #expect(findBoxRecursive(mediaSegment, type: "saio") != nil, "Missing saio in encrypted traf")
        print("✅ Encrypted traf has: senc, saiz, saio")
    }

    // MARK: - 5. Data Offset Validation

    @Test("trun data_offset correctly points to mdat payload")
    func trunDataOffsetValidation() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track])

        let markerData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        var sampleData = markerData
        sampleData.append(Data(repeating: 0x00, count: 100))

        let samples = [FMP4Writer.Sample(data: sampleData, duration: 3000, isSync: true)]
        let mediaSegment = writer.generateMediaSegment(trackID: 1, samples: samples, baseDecodeTime: 0)

        guard let trunInfo = findBoxRecursive(mediaSegment, type: "trun") else {
            Issue.record("Missing trun box")
            return
        }

        // Extract data_offset from trun
        // trun: size(4) + type(4) + version/flags(4) + sample_count(4) + data_offset(4)
        let dataOffsetPosition = trunInfo.offset + 16
        guard dataOffsetPosition + 4 <= mediaSegment.count else {
            Issue.record("trun too small for data_offset")
            return
        }

        let offsetData = mediaSegment.subdata(in: dataOffsetPosition..<(dataOffsetPosition + 4))
        let dataOffset = Int(Int32(bigEndian: offsetData.withUnsafeBytes { $0.load(as: Int32.self) }))

        // Verify the marker is at data_offset
        guard dataOffset + 4 <= mediaSegment.count else {
            Issue.record("data_offset \(dataOffset) points beyond segment end")
            return
        }

        let actualData = mediaSegment.subdata(in: dataOffset..<(dataOffset + 4))
        #expect(actualData == markerData, "data_offset should point to sample data start")
        print("✅ trun data_offset (\(dataOffset)) correctly points to mdat payload")
    }

    // MARK: - 6. HLS Playlist Validation

    @Test("HLS playlist has required tags for FairPlay")
    func hlsPlaylistValidation() {
        let playlistConfig = FMP4HLSGenerator.PlaylistConfig(
            targetDuration: 6,
            playlistType: .vod,
            initSegmentURI: "init.mp4"
        )
        let fairPlayConfig = FMP4HLSGenerator.FairPlayConfig.fairPlay(assetID: "test-asset", keyID: testKeyID)
        let generator = FMP4HLSGenerator(config: playlistConfig, encryption: fairPlayConfig)

        let segments = [
            FMP4HLSGenerator.Segment(uri: "segment0.m4s", duration: 6.0),
            FMP4HLSGenerator.Segment(uri: "segment1.m4s", duration: 6.0)
        ]
        let playlist = generator.generateMediaPlaylist(segments: segments)

        #expect(playlist.contains("#EXTM3U"), "Missing #EXTM3U header")
        #expect(playlist.contains("#EXT-X-VERSION:7"), "Should use HLS version 7 for fMP4")
        #expect(playlist.contains("#EXT-X-KEY:METHOD=SAMPLE-AES"), "Missing FairPlay KEY tag")
        #expect(playlist.contains("skd://"), "Missing skd:// key URI")
        #expect(playlist.contains("KEYFORMAT=\"com.apple.streamingkeydelivery\""), "Missing FairPlay keyformat")
        #expect(playlist.contains("#EXT-X-MAP:URI=\"init.mp4\""), "Missing init segment reference")
        #expect(playlist.contains("#EXT-X-INDEPENDENT-SEGMENTS"), "Missing independent segments tag")
        print("✅ HLS playlist contains all required FairPlay tags")
        print("--- Playlist ---\n\(playlist)")
    }

    // MARK: - 7. Full Pipeline Test

    @Test("Complete FairPlay package validates against Apple requirements")
    func completeFairPlayPackageValidation() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV)
        let writer = FMP4Writer(tracks: [track], encryption: encryption)

        // Generate init segment
        let initSegment = writer.generateInitSegment()
        print("\n=== Init Segment Structure ===")
        print("Size: \(initSegment.count) bytes")

        // Validate init segment structure
        var initValid = true
        for boxType in ["ftyp", "moov", "mvhd", "trak", "tkhd", "edts", "elst", "mdia", "mdhd", "hdlr", "minf", "stbl", "stsd", "mvex", "trex", "pssh", "sinf", "tenc"] {
            if findBoxRecursive(initSegment, type: boxType) == nil {
                print("❌ Missing: \(boxType)")
                initValid = false
            } else {
                print("✓ \(boxType)")
            }
        }

        // Generate media segment
        let samples = [
            FMP4Writer.Sample(data: Data(repeating: 0x11, count: 500), duration: 3000, isSync: true),
            FMP4Writer.Sample(data: Data(repeating: 0x22, count: 300), duration: 3000, isSync: false)
        ]
        let mediaSegment = writer.generateMediaSegment(trackID: 1, samples: samples, baseDecodeTime: 0)
        print("\n=== Media Segment Structure ===")
        print("Size: \(mediaSegment.count) bytes")

        var mediaValid = true
        for boxType in ["styp", "moof", "mfhd", "traf", "tfhd", "tfdt", "trun", "senc", "saiz", "saio", "mdat"] {
            if findBoxRecursive(mediaSegment, type: boxType) == nil {
                print("❌ Missing: \(boxType)")
                mediaValid = false
            } else {
                print("✓ \(boxType)")
            }
        }

        // Generate playlist
        let playlistConfig = FMP4HLSGenerator.PlaylistConfig(targetDuration: 6, playlistType: .vod, initSegmentURI: "init.mp4")
        let fairPlayConfig = FMP4HLSGenerator.FairPlayConfig.fairPlay(assetID: "test", keyID: testKeyID)
        let generator = FMP4HLSGenerator(config: playlistConfig, encryption: fairPlayConfig)
        let playlist = generator.generateMediaPlaylist(segments: [FMP4HLSGenerator.Segment(uri: "segment.m4s", duration: 6.0)])

        print("\n=== Playlist ===")
        print(playlist)

        #expect(initValid, "Init segment structure incomplete")
        #expect(mediaValid, "Media segment structure incomplete")
        print("\n✅ Complete FairPlay package validation passed")
    }

    // MARK: - 8. CBCS Encryption Validation

    @Test("CBCS encryption preserves NAL structure")
    func cbcsPreservesNALStructure() {
        let encryptor = CBCSEncryptor(key: testKey, iv: testIV)

        // Create sample with multiple NAL units
        var sample = Data()

        // SPS NAL (type 7) - should stay clear
        sample.append(contentsOf: [0x00, 0x00, 0x00, 0x10]) // Length = 16
        sample.append(0x67) // NAL type 7
        sample.append(Data(repeating: 0x11, count: 15))

        // PPS NAL (type 8) - should stay clear
        sample.append(contentsOf: [0x00, 0x00, 0x00, 0x08]) // Length = 8
        sample.append(0x68) // NAL type 8
        sample.append(Data(repeating: 0x22, count: 7))

        // IDR NAL (type 5) - should be encrypted
        sample.append(contentsOf: [0x00, 0x00, 0x00, 0x40]) // Length = 64
        sample.append(0x65) // NAL type 5
        sample.append(Data(repeating: 0x33, count: 63))

        let result = encryptor.encryptVideoSample(sample, nalLengthSize: 4)

        // Verify output size matches input
        #expect(result.encryptedData.count == sample.count, "Encrypted size should match input size")

        // Verify NAL length prefixes preserved
        // SPS at 0-19 (20 bytes: 4 prefix + 16 data)
        // PPS at 20-31 (12 bytes: 4 prefix + 8 data)
        // IDR at 32-99 (68 bytes: 4 prefix + 64 data)
        #expect(result.encryptedData[0..<4] == sample[0..<4], "First NAL length should be preserved")
        #expect(result.encryptedData[20..<24] == sample[20..<24], "Second NAL length should be preserved")
        #expect(result.encryptedData[32..<36] == sample[32..<36], "Third NAL length should be preserved")

        // Verify NAL types preserved (NAL type is 1 byte after the 4-byte length prefix)
        #expect(result.encryptedData[4] == 0x67, "SPS NAL type should be preserved")
        #expect(result.encryptedData[24] == 0x68, "PPS NAL type should be preserved")
        #expect(result.encryptedData[36] == 0x65, "IDR NAL type should be preserved")

        // Verify SPS and PPS are unchanged (clear)
        #expect(result.encryptedData[0..<20] == sample[0..<20], "SPS should be completely clear")
        #expect(result.encryptedData[20..<28] == sample[20..<28], "PPS should be completely clear")

        // Verify subsamples exist
        #expect(!result.subsamples.isEmpty, "Should have subsample info")

        print("✅ CBCS encryption preserves NAL structure correctly")
        print("   Subsamples: \(result.subsamples.map { "clear:\($0.bytesOfClearData), protected:\($0.bytesOfProtectedData)" })")
    }

    // MARK: - 9. Box Size Validation

    @Test("All boxes have valid sizes that don't overlap or exceed data")
    func boxSizeValidation() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV)
        let writer = FMP4Writer(tracks: [track], encryption: encryption)

        let initSegment = writer.generateInitSegment()
        let samples = [FMP4Writer.Sample(data: Data(repeating: 0xAA, count: 100), duration: 3000, isSync: true)]
        let mediaSegment = writer.generateMediaSegment(trackID: 1, samples: samples, baseDecodeTime: 0)

        // Validate init segment box sizes
        var offset = 0
        var boxCount = 0
        while offset + 8 <= initSegment.count {
            guard let header = parseBoxHeader(initSegment, at: offset) else {
                Issue.record("Failed to parse box at offset \(offset) in init segment")
                break
            }
            #expect(header.size >= 8, "Box \(header.type) has invalid size \(header.size)")
            #expect(offset + header.size <= initSegment.count, "Box \(header.type) extends beyond init segment")
            offset += header.size
            boxCount += 1
            if boxCount > 50 { break }
        }
        #expect(offset == initSegment.count, "Init segment has \(initSegment.count - offset) bytes after last box")

        // Validate media segment box sizes
        offset = 0
        boxCount = 0
        while offset + 8 <= mediaSegment.count {
            guard let header = parseBoxHeader(mediaSegment, at: offset) else {
                Issue.record("Failed to parse box at offset \(offset) in media segment")
                break
            }
            #expect(header.size >= 8, "Box \(header.type) has invalid size \(header.size)")
            #expect(offset + header.size <= mediaSegment.count, "Box \(header.type) extends beyond media segment")
            offset += header.size
            boxCount += 1
            if boxCount > 20 { break }
        }
        #expect(offset == mediaSegment.count, "Media segment has \(mediaSegment.count - offset) bytes after last box")

        print("✅ All box sizes valid in both init and media segments")
    }
}
