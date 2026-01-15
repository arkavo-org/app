import ArgumentParser
import ArkavoMediaKit
import Foundation

// MARK: - CLI Entry Point

@main
struct TestVideoGenerator: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "TestVideoGenerator",
        abstract: "Generate fMP4/HLS test videos for manual testing",
        discussion: """
            Generates test video packages based on the fMP4/HLS test matrix.
            Each scenario creates an init.mp4, media segments, and playlist.m3u8.
            """
    )

    @Option(name: .shortAndLong, help: "Output directory for generated files")
    var output: String?

    @Option(name: .shortAndLong, help: "Specific scenario to generate (e.g., B1, B2, M1)")
    var scenario: String?

    @Flag(name: .shortAndLong, help: "List all available scenarios")
    var list = false

    @Option(name: .shortAndLong, help: "Segment duration in seconds")
    var duration: Int = 6

    @Option(name: [.customShort("n"), .long], help: "Number of segments to generate")
    var segments: Int = 3

    mutating func run() throws {
        if list {
            printScenarios()
            return
        }

        guard let output = output else {
            throw ValidationError("Missing required option '--output <output>'")
        }

        let outputURL = URL(fileURLWithPath: output)
        let generator = VideoTestGenerator(
            outputDir: outputURL,
            segmentDuration: duration,
            segmentCount: segments
        )

        if let scenarioID = scenario?.uppercased() {
            try generator.generate(scenario: scenarioID)
        } else {
            try generator.generateAll()
        }
    }

    func printScenarios() {
        print("""
        Available Test Scenarios:

        Core Playback:
          B1  - Clear init + clear media (unencrypted)
          B2  - Clear init + encrypted media (FairPlay CBCS)

        Manifest Signaling:
          M1  - Single key SAMPLE-AES (FairPlay manifest)
          M3  - Clear (METHOD=NONE, no encryption tags)

        Fragment Boundary:
          F1  - Segment on IDR boundary
          F2  - Mid-GOP boundary (non-aligned)

        CMAF Compliance:
          C1  - CMAF single track (with styp box)

        Reference Profiles:
          P1  - Clear fMP4 HLS VOD (complete package)
          P2  - FairPlay single key (complete encrypted package)

        Usage: TestVideoGenerator -o ./output -s B2
        """)
    }
}

// MARK: - Video Test Generator

struct VideoTestGenerator {
    let outputDir: URL
    let segmentDuration: Int
    let segmentCount: Int

    // Test fixtures (same as HLSFairPlayTestMatrix.swift)
    let testKey = Data(repeating: 0x3C, count: 16)
    let testIV = Data([
        0xD5, 0xFB, 0xD6, 0xB8, 0x2E, 0xD9, 0x3E, 0x4E,
        0xF9, 0x8A, 0xE4, 0x09, 0x31, 0xEE, 0x33, 0xB7,
    ])
    let testKeyID = Data(repeating: 0x12, count: 16)

    // Realistic H.264 720p parameters
    // SPS: High profile, level 3.1, 1280x720
    let sampleSPS = Data([
        0x67, 0x64, 0x00, 0x1F, 0xAC, 0xD9, 0x40, 0x50,
        0x05, 0xBB, 0x01, 0x10, 0x00, 0x00, 0x03, 0x00,
        0x10, 0x00, 0x00, 0x03, 0x03, 0xC0, 0xF1, 0x83,
        0x19, 0x60,
    ])
    let samplePPS = Data([0x68, 0xEE, 0x3C, 0x80])

    func generateAll() throws {
        print("Generating all test scenarios to: \(outputDir.path)")

        try generateB1Clear()
        try generateB2FairPlay()
        try generateM1SampleAES()
        try generateM3Clear()
        try generateF1IDRBoundary()
        try generateF2MidGOP()
        try generateC1CMAF()
        try generateP1VODClear()
        try generateP2FairPlaySingleKey()

        print("\nAll scenarios generated successfully!")
    }

    func generate(scenario: String) throws {
        switch scenario {
        case "B1":
            try generateB1Clear()
        case "B2":
            try generateB2FairPlay()
        case "M1":
            try generateM1SampleAES()
        case "M3":
            try generateM3Clear()
        case "F1":
            try generateF1IDRBoundary()
        case "F2":
            try generateF2MidGOP()
        case "C1":
            try generateC1CMAF()
        case "P1":
            try generateP1VODClear()
        case "P2":
            try generateP2FairPlaySingleKey()
        default:
            throw ValidationError("Unknown scenario: \(scenario). Use --list to see available scenarios.")
        }
    }

    // MARK: - B1: Clear Init + Clear Media

    func generateB1Clear() throws {
        let dir = outputDir.appendingPathComponent("B1-clear")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1280, height: 720, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track], encryption: nil)

        // Generate init segment
        let initData = writer.generateInitSegment()
        try initData.write(to: dir.appendingPathComponent("init.mp4"))

        // Generate media segments
        var hlsSegments: [FMP4HLSGenerator.Segment] = []
        for i in 0..<segmentCount {
            let samples = createSamples(duration: segmentDuration, startWithIDR: true)
            let baseTime = UInt64(i * segmentDuration * 90000)
            let segmentData = writer.generateMediaSegment(
                trackID: 1, samples: samples, baseDecodeTime: baseTime
            )
            let filename = "segment\(i).m4s"
            try segmentData.write(to: dir.appendingPathComponent(filename))
            hlsSegments.append(.init(uri: filename, duration: Double(segmentDuration)))
        }

        // Generate playlist (clear, no encryption)
        let hlsConfig = FMP4HLSGenerator.PlaylistConfig(
            targetDuration: segmentDuration,
            playlistType: .vod
        )
        let hlsGen = FMP4HLSGenerator(config: hlsConfig, encryption: nil)
        let playlist = hlsGen.generateMediaPlaylist(segments: hlsSegments)
        try playlist.write(
            to: dir.appendingPathComponent("playlist.m3u8"),
            atomically: true, encoding: .utf8
        )

        print("Generated B1-clear: \(dir.path)")
    }

    // MARK: - B2: Clear Init + Encrypted Media (FairPlay)

    func generateB2FairPlay() throws {
        let dir = outputDir.appendingPathComponent("B2-fairplay")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV)
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1280, height: 720, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track], encryption: encryption)

        // Generate init segment (has encryption signaling but clear data)
        let initData = writer.generateInitSegment()
        try initData.write(to: dir.appendingPathComponent("init.mp4"))

        // Generate encrypted media segments
        var hlsSegments: [FMP4HLSGenerator.Segment] = []
        for i in 0..<segmentCount {
            let samples = createSamples(duration: segmentDuration, startWithIDR: true)
            let baseTime = UInt64(i * segmentDuration * 90000)
            let segmentData = writer.generateMediaSegment(
                trackID: 1, samples: samples, baseDecodeTime: baseTime
            )
            let filename = "segment\(i).m4s"
            try segmentData.write(to: dir.appendingPathComponent(filename))
            hlsSegments.append(.init(uri: filename, duration: Double(segmentDuration)))
        }

        // Generate playlist with FairPlay encryption
        let hlsConfig = FMP4HLSGenerator.PlaylistConfig(
            targetDuration: segmentDuration,
            playlistType: .vod
        )
        let fairplayConfig = FMP4HLSGenerator.FairPlayConfig.fairPlay(
            assetID: "test-asset-b2",
            keyID: testKeyID,
            iv: testIV
        )
        let hlsGen = FMP4HLSGenerator(config: hlsConfig, encryption: fairplayConfig)
        let playlist = hlsGen.generateMediaPlaylist(segments: hlsSegments)
        try playlist.write(
            to: dir.appendingPathComponent("playlist.m3u8"),
            atomically: true, encoding: .utf8
        )

        print("Generated B2-fairplay: \(dir.path)")
    }

    // MARK: - M1: Single Key SAMPLE-AES

    func generateM1SampleAES() throws {
        let dir = outputDir.appendingPathComponent("M1-sample-aes")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV)
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1280, height: 720, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track], encryption: encryption)

        let initData = writer.generateInitSegment()
        try initData.write(to: dir.appendingPathComponent("init.mp4"))

        var hlsSegments: [FMP4HLSGenerator.Segment] = []
        for i in 0..<segmentCount {
            let samples = createSamples(duration: segmentDuration, startWithIDR: true)
            let baseTime = UInt64(i * segmentDuration * 90000)
            let segmentData = writer.generateMediaSegment(
                trackID: 1, samples: samples, baseDecodeTime: baseTime
            )
            let filename = "segment\(i).m4s"
            try segmentData.write(to: dir.appendingPathComponent(filename))
            hlsSegments.append(.init(uri: filename, duration: Double(segmentDuration)))
        }

        // Playlist with METHOD=SAMPLE-AES and skd:// URI
        let hlsConfig = FMP4HLSGenerator.PlaylistConfig(
            targetDuration: segmentDuration,
            playlistType: .vod
        )
        let fairplayConfig = FMP4HLSGenerator.FairPlayConfig(
            keyURI: "skd://test-asset-m1",
            keyID: testKeyID,
            iv: testIV
        )
        let hlsGen = FMP4HLSGenerator(config: hlsConfig, encryption: fairplayConfig)
        let playlist = hlsGen.generateMediaPlaylist(segments: hlsSegments)
        try playlist.write(
            to: dir.appendingPathComponent("playlist.m3u8"),
            atomically: true, encoding: .utf8
        )

        print("Generated M1-sample-aes: \(dir.path)")
    }

    // MARK: - M3: Clear (METHOD=NONE)

    func generateM3Clear() throws {
        let dir = outputDir.appendingPathComponent("M3-clear")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Clear content with no encryption
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1280, height: 720, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track], encryption: nil)

        let initData = writer.generateInitSegment()
        try initData.write(to: dir.appendingPathComponent("init.mp4"))

        var hlsSegments: [FMP4HLSGenerator.Segment] = []
        for i in 0..<segmentCount {
            let samples = createSamples(duration: segmentDuration, startWithIDR: true)
            let baseTime = UInt64(i * segmentDuration * 90000)
            let segmentData = writer.generateMediaSegment(
                trackID: 1, samples: samples, baseDecodeTime: baseTime
            )
            let filename = "segment\(i).m4s"
            try segmentData.write(to: dir.appendingPathComponent(filename))
            hlsSegments.append(.init(uri: filename, duration: Double(segmentDuration)))
        }

        // Playlist with no EXT-X-KEY tag
        let hlsConfig = FMP4HLSGenerator.PlaylistConfig(
            targetDuration: segmentDuration,
            playlistType: .vod
        )
        let hlsGen = FMP4HLSGenerator(config: hlsConfig, encryption: nil)
        let playlist = hlsGen.generateMediaPlaylist(segments: hlsSegments)
        try playlist.write(
            to: dir.appendingPathComponent("playlist.m3u8"),
            atomically: true, encoding: .utf8
        )

        print("Generated M3-clear: \(dir.path)")
    }

    // MARK: - F1: Segment on IDR Boundary

    func generateF1IDRBoundary() throws {
        let dir = outputDir.appendingPathComponent("F1-idr-boundary")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1280, height: 720, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track], encryption: nil)

        let initData = writer.generateInitSegment()
        try initData.write(to: dir.appendingPathComponent("init.mp4"))

        // Each segment starts with IDR (proper GOP alignment)
        var hlsSegments: [FMP4HLSGenerator.Segment] = []
        for i in 0..<segmentCount {
            let samples = createSamples(duration: segmentDuration, startWithIDR: true)
            let baseTime = UInt64(i * segmentDuration * 90000)
            let segmentData = writer.generateMediaSegment(
                trackID: 1, samples: samples, baseDecodeTime: baseTime
            )
            let filename = "segment\(i).m4s"
            try segmentData.write(to: dir.appendingPathComponent(filename))
            hlsSegments.append(.init(uri: filename, duration: Double(segmentDuration)))
        }

        let hlsConfig = FMP4HLSGenerator.PlaylistConfig(
            targetDuration: segmentDuration,
            playlistType: .vod
        )
        let hlsGen = FMP4HLSGenerator(config: hlsConfig, encryption: nil)
        let playlist = hlsGen.generateMediaPlaylist(segments: hlsSegments)
        try playlist.write(
            to: dir.appendingPathComponent("playlist.m3u8"),
            atomically: true, encoding: .utf8
        )

        print("Generated F1-idr-boundary: \(dir.path)")
    }

    // MARK: - F2: Mid-GOP Boundary

    func generateF2MidGOP() throws {
        let dir = outputDir.appendingPathComponent("F2-mid-gop")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1280, height: 720, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track], encryption: nil)

        let initData = writer.generateInitSegment()
        try initData.write(to: dir.appendingPathComponent("init.mp4"))

        // First segment starts with IDR, subsequent don't (mid-GOP)
        var hlsSegments: [FMP4HLSGenerator.Segment] = []
        for i in 0..<segmentCount {
            let startWithIDR = (i == 0)  // Only first segment has IDR at start
            let samples = createSamples(duration: segmentDuration, startWithIDR: startWithIDR)
            let baseTime = UInt64(i * segmentDuration * 90000)
            let segmentData = writer.generateMediaSegment(
                trackID: 1, samples: samples, baseDecodeTime: baseTime
            )
            let filename = "segment\(i).m4s"
            try segmentData.write(to: dir.appendingPathComponent(filename))
            hlsSegments.append(.init(uri: filename, duration: Double(segmentDuration)))
        }

        let hlsConfig = FMP4HLSGenerator.PlaylistConfig(
            targetDuration: segmentDuration,
            playlistType: .vod
        )
        let hlsGen = FMP4HLSGenerator(config: hlsConfig, encryption: nil)
        let playlist = hlsGen.generateMediaPlaylist(segments: hlsSegments)
        try playlist.write(
            to: dir.appendingPathComponent("playlist.m3u8"),
            atomically: true, encoding: .utf8
        )

        print("Generated F2-mid-gop: \(dir.path)")
    }

    // MARK: - C1: CMAF Single Track

    func generateC1CMAF() throws {
        let dir = outputDir.appendingPathComponent("C1-cmaf")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // CMAF single track - same as clear but validates styp box presence
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1280, height: 720, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track], encryption: nil)

        let initData = writer.generateInitSegment()
        try initData.write(to: dir.appendingPathComponent("init.mp4"))

        var hlsSegments: [FMP4HLSGenerator.Segment] = []
        for i in 0..<segmentCount {
            let samples = createSamples(duration: segmentDuration, startWithIDR: true)
            let baseTime = UInt64(i * segmentDuration * 90000)
            let segmentData = writer.generateMediaSegment(
                trackID: 1, samples: samples, baseDecodeTime: baseTime
            )
            let filename = "segment\(i).m4s"
            try segmentData.write(to: dir.appendingPathComponent(filename))
            hlsSegments.append(.init(uri: filename, duration: Double(segmentDuration)))
        }

        let hlsConfig = FMP4HLSGenerator.PlaylistConfig(
            targetDuration: segmentDuration,
            playlistType: .vod
        )
        let hlsGen = FMP4HLSGenerator(config: hlsConfig, encryption: nil)
        let playlist = hlsGen.generateMediaPlaylist(segments: hlsSegments)
        try playlist.write(
            to: dir.appendingPathComponent("playlist.m3u8"),
            atomically: true, encoding: .utf8
        )

        print("Generated C1-cmaf: \(dir.path)")
    }

    // MARK: - P1: Clear fMP4 HLS VOD (Reference)

    func generateP1VODClear() throws {
        let dir = outputDir.appendingPathComponent("P1-vod-clear")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1280, height: 720, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track], encryption: nil)

        let initData = writer.generateInitSegment()
        try initData.write(to: dir.appendingPathComponent("init.mp4"))

        var hlsSegments: [FMP4HLSGenerator.Segment] = []
        for i in 0..<segmentCount {
            let samples = createSamples(duration: segmentDuration, startWithIDR: true)
            let baseTime = UInt64(i * segmentDuration * 90000)
            let segmentData = writer.generateMediaSegment(
                trackID: 1, samples: samples, baseDecodeTime: baseTime
            )
            let filename = "segment\(i).m4s"
            try segmentData.write(to: dir.appendingPathComponent(filename))
            hlsSegments.append(.init(uri: filename, duration: Double(segmentDuration)))
        }

        let hlsConfig = FMP4HLSGenerator.PlaylistConfig(
            targetDuration: segmentDuration,
            playlistType: .vod
        )
        let hlsGen = FMP4HLSGenerator(config: hlsConfig, encryption: nil)
        let playlist = hlsGen.generateMediaPlaylist(segments: hlsSegments)
        try playlist.write(
            to: dir.appendingPathComponent("playlist.m3u8"),
            atomically: true, encoding: .utf8
        )

        print("Generated P1-vod-clear: \(dir.path)")
    }

    // MARK: - P2: FairPlay Single Key (Reference)

    func generateP2FairPlaySingleKey() throws {
        let dir = outputDir.appendingPathComponent("P2-fairplay-single-key")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encryption = FMP4Writer.EncryptionConfig(keyID: testKeyID, constantIV: testIV)
        let track = FMP4Writer.TrackConfig.h264Video(
            width: 1280, height: 720, timescale: 90000,
            sps: [sampleSPS], pps: [samplePPS]
        )
        let writer = FMP4Writer(tracks: [track], encryption: encryption)

        let initData = writer.generateInitSegment()
        try initData.write(to: dir.appendingPathComponent("init.mp4"))

        var hlsSegments: [FMP4HLSGenerator.Segment] = []
        for i in 0..<segmentCount {
            let samples = createSamples(duration: segmentDuration, startWithIDR: true)
            let baseTime = UInt64(i * segmentDuration * 90000)
            let segmentData = writer.generateMediaSegment(
                trackID: 1, samples: samples, baseDecodeTime: baseTime
            )
            let filename = "segment\(i).m4s"
            try segmentData.write(to: dir.appendingPathComponent(filename))
            hlsSegments.append(.init(uri: filename, duration: Double(segmentDuration)))
        }

        let hlsConfig = FMP4HLSGenerator.PlaylistConfig(
            targetDuration: segmentDuration,
            playlistType: .vod
        )
        let fairplayConfig = FMP4HLSGenerator.FairPlayConfig.fairPlay(
            assetID: "test-asset-p2",
            keyID: testKeyID,
            iv: testIV
        )
        let hlsGen = FMP4HLSGenerator(config: hlsConfig, encryption: fairplayConfig)
        let playlist = hlsGen.generateMediaPlaylist(segments: hlsSegments)
        try playlist.write(
            to: dir.appendingPathComponent("playlist.m3u8"),
            atomically: true, encoding: .utf8
        )

        print("Generated P2-fairplay-single-key: \(dir.path)")
    }

    // MARK: - Sample Creation

    func createSamples(duration: Int, startWithIDR: Bool) -> [FMP4Writer.Sample] {
        var samples: [FMP4Writer.Sample] = []
        let framesPerSecond = 30
        let frameDuration: UInt32 = 90000 / UInt32(framesPerSecond)  // 3000 ticks
        let totalFrames = duration * framesPerSecond

        for i in 0..<totalFrames {
            // IDR every 30 frames (1 second GOP) or first frame if startWithIDR
            let isIDR: Bool
            if i == 0 {
                isIDR = startWithIDR
            } else {
                isIDR = (i % 30 == 0)
            }

            let data = createVideoSample(isIDR: isIDR)
            samples.append(FMP4Writer.Sample(
                data: data,
                duration: frameDuration,
                isSync: isIDR
            ))
        }
        return samples
    }

    func createVideoSample(isIDR: Bool) -> Data {
        var data = Data()

        // NAL unit with 4-byte length prefix (Annex B to AVCC format)
        let nalType: UInt8 = isIDR ? 0x65 : 0x41  // IDR slice (5) vs non-IDR P-slice (1)

        // Create slice header + fake slice data
        // For IDR: larger to simulate keyframe (~8KB)
        // For P-frame: smaller (~2KB)
        let payloadSize = isIDR ? 8000 : 2000
        var nalData = Data([nalType])
        nalData.append(Data(repeating: 0xAB, count: payloadSize))

        // Write NAL length (big-endian 4 bytes)
        let length = UInt32(nalData.count)
        withUnsafeBytes(of: length.bigEndian) { data.append(contentsOf: $0) }
        data.append(nalData)

        return data
    }
}
