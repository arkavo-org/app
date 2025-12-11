import AVFoundation
import CoreMedia
import Foundation

/// FLV Demuxer for parsing RTMP video/audio payloads
///
/// Extracts H.264 NALUs and AAC frames from FLV tag payloads.
public struct FLVDemuxer: Sendable {
    // MARK: - Types

    public enum DemuxError: Error, LocalizedError {
        case invalidData
        case unsupportedCodec(String)
        case missingSequenceHeader
        case invalidNALU

        public var errorDescription: String? {
            switch self {
            case .invalidData:
                return "Invalid FLV data"
            case let .unsupportedCodec(codec):
                return "Unsupported codec: \(codec)"
            case .missingSequenceHeader:
                return "Missing sequence header"
            case .invalidNALU:
                return "Invalid NALU data"
            }
        }
    }

    /// Parsed video frame
    public struct VideoFrame: Sendable {
        public let nalus: [Data]  // H.264 NALUs without start codes
        public let isKeyframe: Bool
        public let compositionTime: Int32  // CTS offset in ms
        public let pts: CMTime
        public let dts: CMTime
    }

    /// Parsed audio frame
    public struct AudioFrame: Sendable {
        public let data: Data  // Raw AAC frame
        public let pts: CMTime
    }

    /// AVC (H.264) decoder configuration
    public struct AVCDecoderConfig: Sendable {
        public let sps: Data
        public let pps: Data
        public let profileIndication: UInt8
        public let profileCompatibility: UInt8
        public let levelIndication: UInt8
        public let naluLengthSize: UInt8  // Usually 4

        public func createFormatDescription() throws -> CMVideoFormatDescription {
            var formatDescription: CMVideoFormatDescription?

            // Create arrays for parameter sets
            let spsArray = [UInt8](sps)
            let ppsArray = [UInt8](pps)
            let parameterSetSizes: [Int] = [spsArray.count, ppsArray.count]

            // Use nested withUnsafeBufferPointer to ensure pointers remain valid
            let status = spsArray.withUnsafeBufferPointer { spsBuffer in
                ppsArray.withUnsafeBufferPointer { ppsBuffer in
                    // Create array of pointers inside the safe scope
                    var parameterSetPointers: [UnsafePointer<UInt8>] = [
                        spsBuffer.baseAddress!,
                        ppsBuffer.baseAddress!,
                    ]
                    return parameterSetPointers.withUnsafeMutableBufferPointer { pointersBuffer in
                        parameterSetSizes.withUnsafeBufferPointer { sizesBuffer in
                            CMVideoFormatDescriptionCreateFromH264ParameterSets(
                                allocator: kCFAllocatorDefault,
                                parameterSetCount: 2,
                                parameterSetPointers: pointersBuffer.baseAddress!,
                                parameterSetSizes: sizesBuffer.baseAddress!,
                                nalUnitHeaderLength: Int32(naluLengthSize),
                                formatDescriptionOut: &formatDescription
                            )
                        }
                    }
                }
            }

            guard status == noErr, let desc = formatDescription else {
                print("🔍 [FLVDemux] ❌ createFormatDescription failed: status=\(status)")
                throw DemuxError.invalidData
            }

            print("🔍 [FLVDemux] ✅ createFormatDescription succeeded")
            return desc
        }
    }

    /// AAC decoder configuration
    public struct AACDecoderConfig: Sendable {
        public let audioSpecificConfig: Data
        public let sampleRate: Int
        public let channelCount: Int

        public func createFormatDescription() throws -> CMAudioFormatDescription {
            // Parse AudioSpecificConfig
            guard audioSpecificConfig.count >= 2 else {
                throw DemuxError.invalidData
            }

            // Build ASBD
            var asbd = AudioStreamBasicDescription(
                mSampleRate: Float64(sampleRate),
                mFormatID: kAudioFormatMPEG4AAC,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 1024,
                mBytesPerFrame: 0,
                mChannelsPerFrame: UInt32(channelCount),
                mBitsPerChannel: 0,
                mReserved: 0
            )

            var formatDescription: CMAudioFormatDescription?

            let status = CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &asbd,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: audioSpecificConfig.count,
                magicCookie: (audioSpecificConfig as NSData).bytes,
                extensions: nil,
                formatDescriptionOut: &formatDescription
            )

            guard status == noErr, let desc = formatDescription else {
                throw DemuxError.invalidData
            }

            return desc
        }
    }

    // MARK: - Static Methods

    /// Parse AVC (H.264) sequence header from FLV video tag
    public static func parseAVCSequenceHeader(_ data: Data) throws -> AVCDecoderConfig {
        // FLV video tag format:
        // byte 0: frame type (4 bits) | codec id (4 bits)
        // byte 1: AVC packet type (0 = sequence header)
        // bytes 2-4: composition time (signed 24-bit)
        // bytes 5+: AVCDecoderConfigurationRecord

        print("🔍 [FLVDemux] parseAVCSequenceHeader: \(data.count) bytes")
        print("🔍 [FLVDemux] Raw hex: \(data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " "))")

        guard data.count > 5 else {
            print("🔍 [FLVDemux] ❌ Data too short: \(data.count) <= 5")
            throw DemuxError.invalidData
        }

        let codecId = data[0] & 0x0F
        guard codecId == 7 else {  // AVC
            print("🔍 [FLVDemux] ❌ Not AVC codec: \(codecId)")
            throw DemuxError.unsupportedCodec("Video codec \(codecId) is not AVC")
        }

        let avcPacketType = data[1]
        guard avcPacketType == 0 else {
            print("🔍 [FLVDemux] ❌ Not sequence header: packetType=\(avcPacketType)")
            throw DemuxError.invalidData
        }

        // Parse AVCDecoderConfigurationRecord starting at byte 5
        let config = data.subdata(in: 5 ..< data.count)
        print("🔍 [FLVDemux] Config bytes: \(config.count), hex: \(config.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " "))")

        guard config.count >= 7 else {
            print("🔍 [FLVDemux] ❌ Config too short: \(config.count) < 7")
            throw DemuxError.invalidData
        }

        let configVersion = config[0]
        let profileIndication = config[1]
        let profileCompatibility = config[2]
        let levelIndication = config[3]
        let naluLengthSize = (config[4] & 0x03) + 1
        print("🔍 [FLVDemux] version=\(configVersion) profile=\(profileIndication) level=\(levelIndication) naluSize=\(naluLengthSize)")

        // Parse SPS
        let numSPS = config[5] & 0x1F
        print("🔍 [FLVDemux] numSPS=\(numSPS)")
        guard numSPS >= 1 else {
            print("🔍 [FLVDemux] ❌ No SPS: numSPS=\(numSPS)")
            throw DemuxError.invalidData
        }

        var offset = 6
        guard config.count > offset + 2 else {
            print("🔍 [FLVDemux] ❌ Config too short for SPS length: \(config.count) <= \(offset + 2)")
            throw DemuxError.invalidData
        }

        let spsLength = Int(config[offset]) << 8 | Int(config[offset + 1])
        print("🔍 [FLVDemux] spsLength=\(spsLength) at offset \(offset)")
        offset += 2

        guard config.count >= offset + spsLength else {
            print("🔍 [FLVDemux] ❌ Config too short for SPS data: \(config.count) < \(offset + spsLength)")
            throw DemuxError.invalidData
        }

        let sps = config.subdata(in: offset ..< offset + spsLength)
        offset += spsLength
        print("🔍 [FLVDemux] SPS: \(sps.count) bytes")

        // Parse PPS
        guard config.count > offset else {
            print("🔍 [FLVDemux] ❌ Config too short for numPPS: \(config.count) <= \(offset)")
            throw DemuxError.invalidData
        }

        let numPPS = config[offset]
        print("🔍 [FLVDemux] numPPS=\(numPPS)")
        offset += 1

        guard numPPS >= 1, config.count > offset + 2 else {
            print("🔍 [FLVDemux] ❌ Config too short for PPS length: numPPS=\(numPPS), configLen=\(config.count), offset=\(offset)")
            throw DemuxError.invalidData
        }

        let ppsLength = Int(config[offset]) << 8 | Int(config[offset + 1])
        print("🔍 [FLVDemux] ppsLength=\(ppsLength) at offset \(offset)")
        offset += 2

        guard config.count >= offset + ppsLength else {
            print("🔍 [FLVDemux] ❌ Config too short for PPS data: \(config.count) < \(offset + ppsLength)")
            throw DemuxError.invalidData
        }

        let pps = config.subdata(in: offset ..< offset + ppsLength)
        print("🔍 [FLVDemux] ✅ Parsed: SPS=\(sps.count) bytes, PPS=\(pps.count) bytes")

        return AVCDecoderConfig(
            sps: sps,
            pps: pps,
            profileIndication: profileIndication,
            profileCompatibility: profileCompatibility,
            levelIndication: levelIndication,
            naluLengthSize: naluLengthSize
        )
    }

    /// Parse AAC sequence header from FLV audio tag
    public static func parseAACSequenceHeader(_ data: Data) throws -> AACDecoderConfig {
        // FLV audio tag format:
        // byte 0: sound format (4 bits) | rate (2 bits) | size (1 bit) | type (1 bit)
        // byte 1: AAC packet type (0 = sequence header)
        // bytes 2+: AudioSpecificConfig

        guard data.count >= 4 else {
            throw DemuxError.invalidData
        }

        let soundFormat = (data[0] >> 4) & 0x0F
        guard soundFormat == 10 else {  // AAC
            throw DemuxError.unsupportedCodec("Audio format \(soundFormat) is not AAC")
        }

        let aacPacketType = data[1]
        guard aacPacketType == 0 else {
            throw DemuxError.invalidData
        }

        let audioSpecificConfig = data.subdata(in: 2 ..< data.count)

        // Parse AudioSpecificConfig to get sample rate and channels
        guard audioSpecificConfig.count >= 2 else {
            throw DemuxError.invalidData
        }

        let byte0 = audioSpecificConfig[0]
        let byte1 = audioSpecificConfig[1]

        // audioObjectType = (byte0 >> 3) & 0x1F
        let samplingFrequencyIndex = ((byte0 & 0x07) << 1) | ((byte1 >> 7) & 0x01)
        let channelConfiguration = (byte1 >> 3) & 0x0F

        let sampleRates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
        let sampleRate = samplingFrequencyIndex < sampleRates.count ? sampleRates[Int(samplingFrequencyIndex)] : 44100

        return AACDecoderConfig(
            audioSpecificConfig: audioSpecificConfig,
            sampleRate: sampleRate,
            channelCount: Int(channelConfiguration)
        )
    }

    /// Parse AVC (H.264) video frame from FLV video tag
    public static func parseAVCVideoFrame(_ data: Data, naluLengthSize: Int, baseTimestamp: UInt32) throws -> VideoFrame {
        guard data.count > 5 else {
            print("🔍 [FLVDemux] parseAVCVideoFrame: data too short (\(data.count) <= 5)")
            throw DemuxError.invalidData
        }

        let frameType = (data[0] >> 4) & 0x0F
        let codecId = data[0] & 0x0F
        let isKeyframe = frameType == 1

        let avcPacketType = data[1]

        // Debug logging disabled - was too verbose
        // let hexPrefix = data.prefix(14).map { String(format: "%02X", $0) }.joined(separator: " ")
        // print("🔍 [FLVDemux] parseAVCVideoFrame: frameType=\(frameType) codecId=\(codecId) avcPacketType=\(avcPacketType) hex=\(hexPrefix)")

        guard avcPacketType == 1 else {  // NALU
            print("🔍 [FLVDemux] ❌ Not NALU data (avcPacketType=\(avcPacketType), expected 1)")
            throw DemuxError.invalidData
        }

        // Composition time offset (signed 24-bit)
        let ct0 = Int32(data[2])
        let ct1 = Int32(data[3])
        let ct2 = Int32(data[4])
        var compositionTime = (ct0 << 16) | (ct1 << 8) | ct2
        // Sign extend if negative
        if compositionTime & 0x0080_0000 != 0 {
            compositionTime |= Int32(bitPattern: 0xFF00_0000)
        }

        // Parse NALUs
        var nalus: [Data] = []
        var offset = 5

        // Check for NTDF collection item wire format wrapper
        // Format: 3 bytes IV counter + 3 bytes payload length + encrypted payload
        // The byte at offset 5 is the high byte of IV counter, often starting with 0x02
        if data.count > 11 {
            // Parse as NTDF collection item header
            let ivCounter = (UInt32(data[5]) << 16) | (UInt32(data[6]) << 8) | UInt32(data[7])
            let payloadLength = (Int(data[8]) << 16) | (Int(data[9]) << 8) | Int(data[10])

            // Debug logging disabled - was too verbose
            // print("🔍 [FLVDemux] NTDF wrapper check: ivCounter=\(ivCounter), payloadLength=\(payloadLength), dataLen=\(data.count)")

            // If payload length roughly matches remaining data, this is NTDF-wrapped
            // The actual NALU data starts at offset 11 (5 FLV header + 6 NTDF header)
            if payloadLength > 0 && payloadLength <= data.count - 5 {
                offset = 11
                // print("🔍 [FLVDemux] Detected NTDF collection wrapper, skipping to offset 11")
            }
        }

        // Debug logging disabled - was too verbose
        // if offset + naluLengthSize <= data.count {
        //     var firstLength = 0
        //     for i in 0 ..< naluLengthSize {
        //         firstLength = (firstLength << 8) | Int(data[offset + i])
        //     }
        //     print("🔍 [FLVDemux] First NALU length bytes at offset \(offset): \(data[offset..<min(offset+naluLengthSize, data.count)].map { String(format: "%02X", $0) }.joined(separator: " ")) = \(firstLength), dataLen=\(data.count), naluLengthSize=\(naluLengthSize)")
        // }

        while offset + naluLengthSize <= data.count {
            var naluLength = 0
            for i in 0 ..< naluLengthSize {
                naluLength = (naluLength << 8) | Int(data[offset + i])
            }
            offset += naluLengthSize

            guard offset + naluLength <= data.count else {
                print("🔍 [FLVDemux] NALU length \(naluLength) exceeds data bounds (offset=\(offset), dataLen=\(data.count))")
                break
            }

            let nalu = data.subdata(in: offset ..< offset + naluLength)
            nalus.append(nalu)
            offset += naluLength
        }

        // print("🔍 [FLVDemux] Parsed \(nalus.count) NALUs")

        // Calculate timestamps
        let dts = CMTime(value: CMTimeValue(baseTimestamp), timescale: 1000)
        let pts = CMTime(value: CMTimeValue(Int64(baseTimestamp) + Int64(compositionTime)), timescale: 1000)

        return VideoFrame(
            nalus: nalus,
            isKeyframe: isKeyframe,
            compositionTime: compositionTime,
            pts: pts,
            dts: dts
        )
    }

    /// Parse AAC audio frame from FLV audio tag
    public static func parseAACAudioFrame(_ data: Data, baseTimestamp: UInt32) throws -> AudioFrame {
        guard data.count > 2 else {
            throw DemuxError.invalidData
        }

        let aacPacketType = data[1]
        guard aacPacketType == 1 else {  // Raw AAC
            throw DemuxError.invalidData
        }

        let aacData = data.subdata(in: 2 ..< data.count)
        let pts = CMTime(value: CMTimeValue(baseTimestamp), timescale: 1000)

        return AudioFrame(data: aacData, pts: pts)
    }

    /// Create CMSampleBuffer from parsed video frame
    public static func createVideoSampleBuffer(
        frame: VideoFrame,
        formatDescription: CMVideoFormatDescription,
        naluLengthSize: Int
    ) throws -> CMSampleBuffer {
        // Combine NALUs with length prefix
        var blockData = Data()
        for nalu in frame.nalus {
            var length = UInt32(nalu.count)
            // Write length in big-endian
            for _ in 0 ..< naluLengthSize {
                let shift = (naluLengthSize - 1) * 8
                blockData.append(UInt8((length >> shift) & 0xFF))
                length <<= 8
            }
            blockData.append(nalu)
        }

        // Create block buffer
        var blockBuffer: CMBlockBuffer?
        let status = blockData.withUnsafeBytes { bufferPointer in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: UnsafeMutableRawPointer(mutating: bufferPointer.baseAddress!),
                blockLength: blockData.count,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: blockData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }

        guard status == noErr, let buffer = blockBuffer else {
            throw DemuxError.invalidData
        }

        // Create sample buffer
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),  // Assume 30fps
            presentationTimeStamp: frame.pts,
            decodeTimeStamp: frame.dts
        )

        var sampleSize = blockData.count

        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: buffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr, let sample = sampleBuffer else {
            throw DemuxError.invalidData
        }

        // Set keyframe attachment
        if frame.isKeyframe {
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true)
            if let array = attachments as? [[CFString: Any]], !array.isEmpty {
                var dict = array[0]
                dict[kCMSampleAttachmentKey_NotSync] = false
                // Note: Can't easily modify attachments after creation
            }
        }

        return sample
    }

    /// Create CMSampleBuffer from parsed audio frame
    public static func createAudioSampleBuffer(
        frame: AudioFrame,
        formatDescription: CMAudioFormatDescription
    ) throws -> CMSampleBuffer {
        // Create block buffer
        var blockBuffer: CMBlockBuffer?
        let blockData = frame.data

        let status = blockData.withUnsafeBytes { bufferPointer in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: UnsafeMutableRawPointer(mutating: bufferPointer.baseAddress!),
                blockLength: blockData.count,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: blockData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }

        guard status == noErr, let buffer = blockBuffer else {
            throw DemuxError.invalidData
        }

        // Create sample buffer
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1024, timescale: 44100),  // AAC frame duration
            presentationTimeStamp: frame.pts,
            decodeTimeStamp: frame.pts
        )

        var sampleSize = blockData.count

        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: buffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr, let sample = sampleBuffer else {
            throw DemuxError.invalidData
        }

        return sample
    }
}
