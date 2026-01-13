import Foundation
import Testing
@testable import ArkavoMediaKit

// MARK: - FairPlay Structure Analysis Tests

/// Deep analysis tests that dump the actual structure of generated fMP4 content
/// to identify exact issues with FairPlay playback.
@Suite("FairPlay Structure Analysis")
struct FairPlayStructureAnalysisTests {

    let sampleSPS = Data([0x67, 0x64, 0x00, 0x28, 0xAC, 0xD9, 0x40, 0x78,
                          0x02, 0x27, 0xE5, 0xC0, 0x44, 0x00, 0x00, 0x03,
                          0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0xF2, 0x3C,
                          0x60, 0xC6, 0x58])
    let samplePPS = Data([0x68, 0xEE, 0x3C, 0x80])
    let testKeyID = Data(repeating: 0x12, count: 16)
    let testIV = Data([0xD5, 0xFB, 0xD6, 0xB8, 0x2E, 0xD9, 0x3E, 0x4E,
                       0xF9, 0x8A, 0xE4, 0x09, 0x31, 0xEE, 0x33, 0xB7])

    // MARK: - Hex Dump Helper

    private func hexDump(_ data: Data, maxBytes: Int = 200) -> String {
        var result = ""
        let bytes = min(data.count, maxBytes)
        for i in stride(from: 0, to: bytes, by: 16) {
            let lineBytes = min(16, bytes - i)
            let hex = data[i..<(i + lineBytes)].map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = data[i..<(i + lineBytes)].map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "." }.map(String.init).joined()
            result += String(format: "%04X: %-48s %s\n", i, hex, ascii)
        }
        if data.count > maxBytes {
            result += "... (\(data.count - maxBytes) more bytes)\n"
        }
        return result
    }

    // MARK: - Box Parsing

    private func parseAndDumpBoxes(_ data: Data, startOffset: Int = 0, indent: String = "", maxDepth: Int = 5) -> String {
        guard maxDepth > 0 else { return "" }
        var result = ""
        var offset = startOffset

        while offset + 8 <= data.count {
            let sizeData = data.subdata(in: offset..<(offset + 4))
            var size = Int(UInt32(bigEndian: sizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))
            let typeData = data.subdata(in: (offset + 4)..<(offset + 8))
            guard let type = String(data: typeData, encoding: .ascii) else { break }

            var headerSize = 8
            if size == 1 && offset + 16 <= data.count {
                let extSizeData = data.subdata(in: (offset + 8)..<(offset + 16))
                size = Int(UInt64(bigEndian: extSizeData.withUnsafeBytes { $0.load(as: UInt64.self) }))
                headerSize = 16
            }

            guard size >= headerSize, offset + size <= data.count else { break }

            result += "\(indent)\(type) (size: \(size), offset: \(offset))\n"

            // Parse children for container boxes
            let containerTypes = ["moov", "moof", "trak", "mdia", "minf", "stbl", "traf", "mvex", "edts", "dinf", "sinf", "schi"]
            if containerTypes.contains(type) {
                result += parseAndDumpBoxes(data, startOffset: offset + headerSize, indent: indent + "  ", maxDepth: maxDepth - 1)
            } else if type == "stsd" {
                // stsd has special structure: version(1) + flags(3) + entry_count(4) + entries
                let entryCountOffset = offset + headerSize + 4
                if entryCountOffset + 4 <= data.count {
                    let entryCountData = data.subdata(in: entryCountOffset..<(entryCountOffset + 4))
                    let entryCount = UInt32(bigEndian: entryCountData.withUnsafeBytes { $0.load(as: UInt32.self) })
                    result += "\(indent)  (entry_count: \(entryCount))\n"
                    // Parse sample entries
                    var entryOffset = entryCountOffset + 4
                    for i in 0..<entryCount {
                        if entryOffset + 8 > offset + size { break }
                        let entrySizeData = data.subdata(in: entryOffset..<(entryOffset + 4))
                        let entrySize = Int(UInt32(bigEndian: entrySizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))
                        let entryTypeData = data.subdata(in: (entryOffset + 4)..<(entryOffset + 8))
                        if let entryType = String(data: entryTypeData, encoding: .ascii) {
                            result += "\(indent)  [\(i)] \(entryType) (size: \(entrySize), offset: \(entryOffset))\n"
                            // Look for sinf inside sample entry (after fixed fields)
                            // Sample entry structure: 78 bytes fixed header + avcC + sinf
                            if entryType == "encv" || entryType == "avc1" || entryType == "hvc1" {
                                var innerOffset = entryOffset + 8 + 70 // Skip to variable part
                                while innerOffset + 8 <= entryOffset + entrySize {
                                    let innerSizeData = data.subdata(in: innerOffset..<(innerOffset + 4))
                                    let innerSize = Int(UInt32(bigEndian: innerSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))
                                    let innerTypeData = data.subdata(in: (innerOffset + 4)..<(innerOffset + 8))
                                    if let innerType = String(data: innerTypeData, encoding: .ascii), innerSize >= 8 {
                                        result += "\(indent)      \(innerType) (size: \(innerSize), offset: \(innerOffset))\n"
                                        if innerType == "sinf" {
                                            result += parseAndDumpBoxes(data, startOffset: innerOffset + 8, indent: indent + "        ", maxDepth: maxDepth - 2)
                                        }
                                    }
                                    if innerSize > 0 { innerOffset += innerSize } else { break }
                                }
                            }
                        }
                        if entrySize > 0 { entryOffset += entrySize } else { break }
                    }
                }
            }

            offset += size
        }
        return result
    }

    // MARK: - Analysis Tests

    @Test("Dump encrypted init segment structure")
    func dumpEncryptedInitStructure() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV)
        let writer = FMP4Writer(tracks: [track], encryption: encryption)
        let initSegment = writer.generateInitSegment()

        print("\n" + String(repeating: "=", count: 60))
        print("ENCRYPTED INIT SEGMENT ANALYSIS")
        print("Total size: \(initSegment.count) bytes")
        print(String(repeating: "=", count: 60))

        print("\n--- Box Structure ---")
        print(parseAndDumpBoxes(initSegment))

        print("\n--- Hex Dump (first 300 bytes) ---")
        print(hexDump(initSegment, maxBytes: 300))

        // Find and dump specific boxes
        print("\n--- Sample Entry Analysis ---")
        // Search for sample entry types
        let encvMarker = Data([0x65, 0x6E, 0x63, 0x76])
        let avc1Marker = Data([0x61, 0x76, 0x63, 0x31])
        let sinfMarker = Data([0x73, 0x69, 0x6E, 0x66])
        let tencMarker = Data([0x74, 0x65, 0x6E, 0x63])
        let frmaMarker = Data([0x66, 0x72, 0x6D, 0x61])

        if let range = initSegment.range(of: encvMarker) {
            print("encv found at offset: \(range.lowerBound)")
        } else {
            print("❌ encv NOT found")
        }

        if let range = initSegment.range(of: avc1Marker) {
            print("avc1 found at offset: \(range.lowerBound) (may be in frma - original format)")
        }

        if let range = initSegment.range(of: sinfMarker) {
            print("sinf found at offset: \(range.lowerBound)")
            // Dump sinf contents
            let sinfStart = range.lowerBound - 4 // Back to size field
            if sinfStart >= 0 && sinfStart + 4 <= initSegment.count {
                let sinfSizeData = initSegment.subdata(in: sinfStart..<(sinfStart + 4))
                let sinfSize = Int(UInt32(bigEndian: sinfSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))
                if sinfStart + sinfSize <= initSegment.count {
                    print("sinf hex dump:")
                    print(hexDump(initSegment.subdata(in: sinfStart..<(sinfStart + sinfSize))))
                }
            }
        } else {
            print("❌ sinf NOT found")
        }

        if let range = initSegment.range(of: tencMarker) {
            print("tenc found at offset: \(range.lowerBound)")
        } else {
            print("❌ tenc NOT found")
        }

        if let range = initSegment.range(of: frmaMarker) {
            print("frma found at offset: \(range.lowerBound)")
        } else {
            print("❌ frma NOT found")
        }

        // This test always passes - it's for diagnostic output
        #expect(Bool(true))
    }

    @Test("Dump encrypted media segment structure")
    func dumpEncryptedMediaStructure() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV)
        let writer = FMP4Writer(tracks: [track], encryption: encryption)

        let samples = [
            FMP4Writer.Sample(data: Data(repeating: 0x11, count: 500), duration: 3000, isSync: true),
            FMP4Writer.Sample(data: Data(repeating: 0x22, count: 300), duration: 3000, isSync: false)
        ]
        let mediaSegment = writer.generateMediaSegment(trackID: 1, samples: samples, baseDecodeTime: 0)

        print("\n" + String(repeating: "=", count: 60))
        print("ENCRYPTED MEDIA SEGMENT ANALYSIS")
        print("Total size: \(mediaSegment.count) bytes")
        print(String(repeating: "=", count: 60))

        print("\n--- Box Structure ---")
        print(parseAndDumpBoxes(mediaSegment))

        print("\n--- traf Contents ---")
        let trafMarker = Data([0x74, 0x72, 0x61, 0x66])
        if let range = mediaSegment.range(of: trafMarker) {
            let trafStart = range.lowerBound - 4
            if trafStart >= 0 && trafStart + 4 <= mediaSegment.count {
                let trafSizeData = mediaSegment.subdata(in: trafStart..<(trafStart + 4))
                let trafSize = Int(UInt32(bigEndian: trafSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))
                if trafStart + trafSize <= mediaSegment.count {
                    print("traf hex dump (first 200 bytes):")
                    let dumpSize = min(200, trafSize)
                    print(hexDump(mediaSegment.subdata(in: trafStart..<(trafStart + dumpSize))))
                }
            }
        }

        // Check for encryption boxes
        let sencMarker = Data([0x73, 0x65, 0x6E, 0x63])
        let saizMarker = Data([0x73, 0x61, 0x69, 0x7A])
        let saioMarker = Data([0x73, 0x61, 0x69, 0x6F])

        print("\n--- Encryption Boxes ---")
        if let range = mediaSegment.range(of: sencMarker) {
            print("✓ senc at offset: \(range.lowerBound)")
        } else {
            print("❌ senc NOT found")
        }

        if let range = mediaSegment.range(of: saizMarker) {
            print("✓ saiz at offset: \(range.lowerBound)")
        } else {
            print("❌ saiz NOT found")
        }

        if let range = mediaSegment.range(of: saioMarker) {
            print("✓ saio at offset: \(range.lowerBound)")
        } else {
            print("❌ saio NOT found")
        }

        #expect(Bool(true))
    }

    @Test("Verify CBCS encryption output structure")
    func verifyCBCSOutput() {
        let key = Data(repeating: 0x3C, count: 16)
        let iv = Data([0xD5, 0xFB, 0xD6, 0xB8, 0x2E, 0xD9, 0x3E, 0x4E,
                       0xF9, 0x8A, 0xE4, 0x09, 0x31, 0xEE, 0x33, 0xB7])
        let encryptor = CBCSEncryptor(key: key, iv: iv)

        // Create a realistic video sample
        var sample = Data()

        // SPS NAL (type 7)
        sample.append(contentsOf: [0x00, 0x00, 0x00, 0x10]) // Length = 16
        sample.append(0x67) // NAL type 7 (SPS)
        sample.append(Data(repeating: 0xAA, count: 15))

        // PPS NAL (type 8)
        sample.append(contentsOf: [0x00, 0x00, 0x00, 0x08]) // Length = 8
        sample.append(0x68) // NAL type 8 (PPS)
        sample.append(Data(repeating: 0xBB, count: 7))

        // IDR NAL (type 5) - larger for encryption
        sample.append(contentsOf: [0x00, 0x00, 0x00, 0x60]) // Length = 96
        sample.append(0x65) // NAL type 5 (IDR)
        sample.append(Data(repeating: 0xCC, count: 95))

        print("\n" + String(repeating: "=", count: 60))
        print("CBCS ENCRYPTION OUTPUT ANALYSIS")
        print("Input size: \(sample.count) bytes")
        print(String(repeating: "=", count: 60))

        print("\n--- Input Sample ---")
        print(hexDump(sample))

        let result = encryptor.encryptVideoSample(sample, nalLengthSize: 4)

        print("\n--- Encrypted Output ---")
        print("Output size: \(result.encryptedData.count) bytes")
        print(hexDump(result.encryptedData))

        print("\n--- Subsamples ---")
        for (i, subsample) in result.subsamples.enumerated() {
            print("[\(i)] clear: \(subsample.bytesOfClearData), protected: \(subsample.bytesOfProtectedData)")
        }

        // Verify structure
        print("\n--- Verification ---")

        // Check NAL length preservation
        let nal1Len = sample[0..<4]
        let nal2Len = sample[20..<24]
        let nal3Len = sample[28..<32]

        let out1Len = result.encryptedData[0..<4]
        let out2Len = result.encryptedData[20..<24]
        let out3Len = result.encryptedData[28..<32]

        print("NAL 1 length preserved: \(nal1Len == out1Len)")
        print("NAL 2 length preserved: \(nal2Len == out2Len)")
        print("NAL 3 length preserved: \(nal3Len == out3Len)")

        // Check NAL types
        print("NAL 1 type preserved: \(sample[4] == result.encryptedData[4]) (0x\(String(format: "%02X", sample[4])) vs 0x\(String(format: "%02X", result.encryptedData[4])))")
        print("NAL 2 type preserved: \(sample[24] == result.encryptedData[24]) (0x\(String(format: "%02X", sample[24])) vs 0x\(String(format: "%02X", result.encryptedData[24])))")
        print("NAL 3 type preserved: \(sample[32] == result.encryptedData[32]) (0x\(String(format: "%02X", sample[32])) vs 0x\(String(format: "%02X", result.encryptedData[32])))")

        // Check that non-VCL NALs are unchanged
        let spsUnchanged = sample[0..<20] == result.encryptedData[0..<20]
        let ppsUnchanged = sample[20..<28] == result.encryptedData[20..<28]
        print("SPS unchanged: \(spsUnchanged)")
        print("PPS unchanged: \(ppsUnchanged)")

        // Verify subsamples total matches output size
        let totalFromSubsamples = result.subsamples.reduce(0) { $0 + Int($1.bytesOfClearData) + Int($1.bytesOfProtectedData) }
        print("Subsamples total: \(totalFromSubsamples), output size: \(result.encryptedData.count)")

        #expect(result.encryptedData.count == sample.count, "Output size must match input size")
        #expect(totalFromSubsamples == result.encryptedData.count, "Subsamples must account for all bytes")
    }

    @Test("Compare unencrypted vs encrypted stsd")
    func compareStsdStructure() {
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1920, height: 1080, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )

        // Unencrypted
        let unencryptedWriter = FMP4Writer(tracks: [track])
        let unencryptedInit = unencryptedWriter.generateInitSegment()

        // Encrypted
        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV)
        let encryptedWriter = FMP4Writer(tracks: [track], encryption: encryption)
        let encryptedInit = encryptedWriter.generateInitSegment()

        print("\n" + String(repeating: "=", count: 60))
        print("STSD STRUCTURE COMPARISON")
        print(String(repeating: "=", count: 60))

        // Find stsd in each
        let stsdMarker = Data([0x73, 0x74, 0x73, 0x64])

        print("\n--- Unencrypted stsd ---")
        if let range = unencryptedInit.range(of: stsdMarker) {
            let stsdStart = range.lowerBound - 4
            if stsdStart >= 0 {
                let stsdSizeData = unencryptedInit.subdata(in: stsdStart..<(stsdStart + 4))
                let stsdSize = Int(UInt32(bigEndian: stsdSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))
                print("stsd at offset \(stsdStart), size \(stsdSize)")
                if stsdStart + stsdSize <= unencryptedInit.count {
                    print(hexDump(unencryptedInit.subdata(in: stsdStart..<(stsdStart + min(stsdSize, 150)))))
                }
            }
        }

        print("\n--- Encrypted stsd ---")
        if let range = encryptedInit.range(of: stsdMarker) {
            let stsdStart = range.lowerBound - 4
            if stsdStart >= 0 {
                let stsdSizeData = encryptedInit.subdata(in: stsdStart..<(stsdStart + 4))
                let stsdSize = Int(UInt32(bigEndian: stsdSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))
                print("stsd at offset \(stsdStart), size \(stsdSize)")
                if stsdStart + stsdSize <= encryptedInit.count {
                    print(hexDump(encryptedInit.subdata(in: stsdStart..<(stsdStart + min(stsdSize, 300)))))
                }
            }
        }

        // Check for sample entry types
        let avc1Marker = Data([0x61, 0x76, 0x63, 0x31])
        let encvMarker = Data([0x65, 0x6E, 0x63, 0x76])

        print("\n--- Sample Entry Types ---")
        print("Unencrypted has avc1: \(unencryptedInit.range(of: avc1Marker) != nil)")
        print("Unencrypted has encv: \(unencryptedInit.range(of: encvMarker) != nil)")
        print("Encrypted has avc1: \(encryptedInit.range(of: avc1Marker) != nil) (expected in frma)")
        print("Encrypted has encv: \(encryptedInit.range(of: encvMarker) != nil)")

        // Check size difference
        print("\nSize difference: \(encryptedInit.count - unencryptedInit.count) bytes")
        print("Expected extra: sinf(~100) + pssh(~50) = ~150 bytes")

        #expect(encryptedInit.range(of: encvMarker) != nil, "Encrypted should have encv")
        #expect(encryptedInit.count > unencryptedInit.count, "Encrypted should be larger due to sinf/pssh")
    }
}
