//
//  MuseIntegrationTests.swift
//  ArkavoCreatorTests
//
//  Integration tests for the Muse AI avatar pipeline:
//  MuseCore package, LLM fallback chain, StreamChatReactor,
//  AudioMixer, TTS audio source, and chat client parsing.
//

@testable import ArkavoCreator
import ArkavoKit
import CoreMedia
import Metal
import MuseCore
import VRMMetalKit
import XCTest

// MARK: - Mock LLM Provider

/// Mock LLM provider for testing the fallback chain without real backends
final class MockLLMProvider: LLMResponseProvider, @unchecked Sendable {
    let providerName: String
    let priority: Int
    var available: Bool
    var responseText: String
    var shouldFail: Bool
    var generateCallCount = 0

    var isAvailable: Bool {
        get async { available }
    }

    init(name: String, priority: Int, available: Bool = true, response: String = "Hello!", shouldFail: Bool = false) {
        self.providerName = name
        self.priority = priority
        self.available = available
        self.responseText = response
        self.shouldFail = shouldFail
    }

    func generate(prompt: String) async throws -> ConstrainedResponse {
        generateCallCount += 1
        if shouldFail {
            throw LLMProviderError.notAvailable(provider: providerName)
        }
        return ConstrainedResponse(message: responseText)
    }
}

// MARK: - LLM Fallback Chain Tests

final class LLMFallbackChainTests: XCTestCase {

    func testSingleProviderGeneration() async throws {
        let chain = LLMFallbackChain()
        let mock = MockLLMProvider(name: "TestProvider", priority: 0, response: "Test response")
        chain.addProvider(mock)

        let (response, provider) = try await chain.generate(prompt: "Hi")
        XCTAssertEqual(response.message, "Test response")
        XCTAssertEqual(provider, "TestProvider")
        XCTAssertEqual(mock.generateCallCount, 1)
    }

    func testFallbackOnFailure() async throws {
        let chain = LLMFallbackChain()
        let failing = MockLLMProvider(name: "Failing", priority: 0, shouldFail: true)
        let fallback = MockLLMProvider(name: "Fallback", priority: 1, response: "Fallback response")
        chain.addProvider(failing)
        chain.addProvider(fallback)

        let (response, provider) = try await chain.generate(prompt: "Hi")
        XCTAssertEqual(response.message, "Fallback response")
        XCTAssertEqual(provider, "Fallback")
        XCTAssertEqual(failing.generateCallCount, 1)
        XCTAssertEqual(fallback.generateCallCount, 1)
    }

    func testSkipsUnavailableProviders() async throws {
        let chain = LLMFallbackChain()
        let unavailable = MockLLMProvider(name: "Unavailable", priority: 0, available: false)
        let available = MockLLMProvider(name: "Available", priority: 1, response: "I'm here")
        chain.addProvider(unavailable)
        chain.addProvider(available)

        let (response, provider) = try await chain.generate(prompt: "Hi")
        XCTAssertEqual(provider, "Available")
        XCTAssertEqual(response.message, "I'm here")
        // Unavailable provider should not have generate() called
        XCTAssertEqual(unavailable.generateCallCount, 0)
    }

    func testAllProvidersFailThrows() async {
        let chain = LLMFallbackChain()
        let failing1 = MockLLMProvider(name: "Fail1", priority: 0, shouldFail: true)
        let failing2 = MockLLMProvider(name: "Fail2", priority: 1, shouldFail: true)
        chain.addProvider(failing1)
        chain.addProvider(failing2)

        do {
            _ = try await chain.generate(prompt: "Hi")
            XCTFail("Expected error when all providers fail")
        } catch {
            // Expected
        }
    }

    func testNoProvidersThrows() async {
        let chain = LLMFallbackChain()

        do {
            _ = try await chain.generate(prompt: "Hi")
            XCTFail("Expected error with no providers")
        } catch {
            // Expected: noProvidersConfigured
        }
    }

    func testGracefulDegradationNeverThrows() async {
        let chain = LLMFallbackChain()
        let failing = MockLLMProvider(name: "Fail", priority: 0, shouldFail: true)
        chain.addProvider(failing)

        let (response, provider) = await chain.generateWithFallback(prompt: "Hi")
        XCTAssertEqual(provider, "Fallback")
        XCTAssertFalse(response.message.isEmpty)
    }

    func testProviderPrioritySorting() async throws {
        let chain = LLMFallbackChain()
        // Add in reverse priority order
        let low = MockLLMProvider(name: "Low", priority: 10, response: "Low priority")
        let high = MockLLMProvider(name: "High", priority: 0, response: "High priority")
        chain.addProvider(low)
        chain.addProvider(high)

        let (response, provider) = try await chain.generate(prompt: "Hi")
        // High priority (lower number) should be tried first
        XCTAssertEqual(provider, "High")
        XCTAssertEqual(response.message, "High priority")
    }
}

// MARK: - ConstrainedResponse Tests

final class ConstrainedResponseTests: XCTestCase {

    func testDecodeSimpleMessage() throws {
        let json = """
        {"message": "Hello there!"}
        """
        let response = try JSONDecoder().decode(ConstrainedResponse.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(response.message, "Hello there!")
        XCTAssertNil(response.toolCall)
    }

    func testConstrainedResponseEquality() {
        let a = ConstrainedResponse(message: "Hi")
        let b = ConstrainedResponse(message: "Hi")
        let c = ConstrainedResponse(message: "Bye")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testConstrainedResponseWithToolCall() {
        let response = ConstrainedResponse(
            message: "Let me wave!",
            toolCall: .playAnimation(animation: "wave", loop: false)
        )
        XCTAssertEqual(response.message, "Let me wave!")
        XCTAssertEqual(response.toolCall, .playAnimation(animation: "wave", loop: false))
    }
}

// MARK: - StreamContextProvider Model Tests

final class StreamContextModelTests: XCTestCase {

    func testChatMessageDefaults() {
        let msg = ChatMessage(
            platform: "twitch",
            username: "testuser",
            displayName: "Test User",
            content: "Hello stream!"
        )

        XCTAssertEqual(msg.platform, "twitch")
        XCTAssertEqual(msg.username, "testuser")
        XCTAssertEqual(msg.displayName, "Test User")
        XCTAssertEqual(msg.content, "Hello stream!")
        XCTAssertFalse(msg.isHighlighted)
        XCTAssertTrue(msg.badges.isEmpty)
        XCTAssertFalse(msg.id.isEmpty)
    }

    func testChatMessageWithBadges() {
        let msg = ChatMessage(
            platform: "twitch",
            username: "sub_user",
            displayName: "Sub User",
            content: "PogChamp",
            badges: ["subscriber", "turbo"],
            isHighlighted: true
        )

        XCTAssertTrue(msg.isHighlighted)
        XCTAssertEqual(msg.badges.count, 2)
        XCTAssertTrue(msg.badges.contains("subscriber"))
    }

    func testStreamEventTypes() {
        let follow = StreamEvent(platform: "twitch", type: .follow, username: "u", displayName: "U")
        let sub = StreamEvent(platform: "twitch", type: .subscribe, username: "u", displayName: "U")
        let donation = StreamEvent(platform: "youtube", type: .donation, username: "u", displayName: "U", amount: 5.0)
        let raid = StreamEvent(platform: "twitch", type: .raid, username: "u", displayName: "U")
        let cheer = StreamEvent(platform: "twitch", type: .cheer, username: "u", displayName: "U", amount: 100)
        let patron = StreamEvent(platform: "patreon", type: .newPatron, username: "u", displayName: "U")
        let social = StreamEvent(platform: "bluesky", type: .socialMention, username: "u", displayName: "U", message: "Hi!")

        XCTAssertEqual(follow.type, .follow)
        XCTAssertEqual(sub.type, .subscribe)
        XCTAssertEqual(donation.amount, 5.0)
        XCTAssertEqual(raid.type, .raid)
        XCTAssertEqual(cheer.amount, 100)
        XCTAssertEqual(patron.type, .newPatron)
        XCTAssertEqual(social.message, "Hi!")
    }

    func testStreamEventDefaultValues() {
        let event = StreamEvent(platform: "twitch", type: .follow, username: "u", displayName: "U")
        XCTAssertNil(event.message)
        XCTAssertNil(event.amount)
        XCTAssertFalse(event.id.isEmpty)
    }
}

// MARK: - StreamChatReactor Tests

@MainActor
final class StreamChatReactorTests: XCTestCase {

    func testReactorStartStop() {
        let reactor = StreamChatReactor()
        XCTAssertFalse(reactor.isRunning)

        reactor.start()
        XCTAssertTrue(reactor.isRunning)

        reactor.stop()
        XCTAssertFalse(reactor.isRunning)
    }

    func testReactorCallbacksRegistered() {
        let reactor = StreamChatReactor()

        var speechCalled = false
        var emoteCalled = false
        var expressionCalled = false

        reactor.onSpeechRequest = { _ in speechCalled = true }
        reactor.onEmoteRequest = { _ in emoteCalled = true }
        reactor.onExpressionRequest = { _, _ in expressionCalled = true }

        // Verify callbacks are set (not nil)
        XCTAssertNotNil(reactor.onSpeechRequest)
        XCTAssertNotNil(reactor.onEmoteRequest)
        XCTAssertNotNil(reactor.onExpressionRequest)

        // Trigger expression callback directly
        reactor.onExpressionRequest?(.happy, 0.5)
        XCTAssertTrue(expressionCalled)

        // Trigger emote callback directly
        reactor.onEmoteRequest?(.wave)
        XCTAssertTrue(emoteCalled)
    }

    func testReactorRateLimitDefaults() {
        let reactor = StreamChatReactor()
        XCTAssertEqual(reactor.responseInterval, 8.0)
        XCTAssertEqual(reactor.maxQueueDepth, 5)
    }
}

// MARK: - AudioMixer Tests

final class AudioMixerTests: XCTestCase {

    func testAudioMixerInit() {
        let mixer = AudioMixer(sampleRate: 48000, channels: 2)
        XCTAssertNotNil(mixer)
    }

    func testAudioMixerDuckingDefault() {
        let mixer = AudioMixer()
        XCTAssertEqual(mixer.ttsActiveDuckAmount, 0.7)
    }

    func testAudioMixerReset() {
        let mixer = AudioMixer()
        // Should not crash
        mixer.reset()
    }

    func testAudioMixerCallbackSet() {
        let mixer = AudioMixer()
        let expectation = XCTestExpectation(description: "Callback set")

        var callbackCalled = false
        mixer.onMixedSample = { _ in
            callbackCalled = true
        }

        XCTAssertNotNil(mixer.onMixedSample)
        expectation.fulfill()
        wait(for: [expectation], timeout: 1.0)
    }

    /// Create a minimal CMSampleBuffer with PCM audio for testing
    private func makePCMSampleBuffer(frameCount: Int = 1024, sampleRate: Double = 48000) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let format = formatDescription else { return nil }

        let dataSize = frameCount * 4  // 2 channels * 2 bytes per sample
        let data = Data(count: dataSize)

        var blockBuffer: CMBlockBuffer?
        data.withUnsafeBytes { rawPtr in
            guard let baseAddress = rawPtr.baseAddress else { return }
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: UnsafeMutableRawPointer(mutating: baseAddress),
                blockLength: dataSize,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: dataSize,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }

        guard let block = blockBuffer else { return nil }

        var sampleBuffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: frameCount,
            presentationTimeStamp: CMTime(value: 0, timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }

    func testAudioMixerSingleSourcePassthrough() {
        let mixer = AudioMixer(sampleRate: 48000, channels: 2)
        let expectation = XCTestExpectation(description: "Mixed sample received")

        mixer.onMixedSample = { buffer in
            XCTAssertNotNil(buffer)
            expectation.fulfill()
        }

        guard let sample = makePCMSampleBuffer() else {
            XCTFail("Failed to create test sample buffer")
            return
        }

        mixer.addSample(sample, from: "microphone")
        wait(for: [expectation], timeout: 2.0)
    }

    func testAudioMixerMultipleSourcesMix() {
        let mixer = AudioMixer(sampleRate: 48000, channels: 2)
        var receivedCount = 0
        let expectation = XCTestExpectation(description: "Mixed samples received")
        expectation.expectedFulfillmentCount = 1

        mixer.onMixedSample = { _ in
            receivedCount += 1
            if receivedCount >= 1 {
                expectation.fulfill()
            }
        }

        guard let sample1 = makePCMSampleBuffer(),
              let sample2 = makePCMSampleBuffer()
        else {
            XCTFail("Failed to create test sample buffers")
            return
        }

        // Add from two sources — should trigger mixing
        mixer.addSample(sample1, from: "microphone")
        mixer.addSample(sample2, from: "muse-tts")

        wait(for: [expectation], timeout: 2.0)
    }
}

// MARK: - MuseTTSAudioSource Tests

final class MuseTTSAudioSourceTests: XCTestCase {

    func testSourceIDAndName() {
        let source = MuseTTSAudioSource()
        XCTAssertEqual(source.sourceID, "muse-tts")
        XCTAssertEqual(source.sourceName, "Muse TTS")
    }

    func testCustomSourceID() {
        let source = MuseTTSAudioSource(sourceID: "custom-tts")
        XCTAssertEqual(source.sourceID, "custom-tts")
    }

    func testInitialState() {
        let source = MuseTTSAudioSource()
        XCTAssertFalse(source.isActive)
        XCTAssertFalse(source.isSpeaking)
    }

    func testAudioFormat() {
        let source = MuseTTSAudioSource()
        let format = source.format
        XCTAssertEqual(format.sampleRate, 48000)
        XCTAssertEqual(format.channels, 1)
    }

    func testStartActivatesSource() async throws {
        let source = MuseTTSAudioSource()
        try await source.start()
        XCTAssertTrue(source.isActive)
        try await source.stop()
        XCTAssertFalse(source.isActive)
    }
}

// MARK: - MuseAvatarViewModel Tests

@MainActor
final class MuseAvatarViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = MuseAvatarViewModel()
        XCTAssertFalse(vm.isModelLoaded)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.error)
        XCTAssertNil(vm.lastChatMessage)
    }

    func testSetupCreatesComponents() {
        let vm = MuseAvatarViewModel()
        vm.setup()

        // On macOS with Metal, renderer should be created
        // (may be nil in CI without GPU)
        if MTLCreateSystemDefaultDevice() != nil {
            XCTAssertNotNil(vm.renderer)
            XCTAssertNotNil(vm.chatReactor)
            XCTAssertNotNil(vm.getAudioSource())
        }
    }

    func testGetAudioSourceReturnsTTS() {
        let vm = MuseAvatarViewModel()
        vm.setup()

        if let source = vm.getAudioSource() {
            XCTAssertEqual(source.sourceID, "muse-tts")
        }
    }

    func testReactToEventUpdatesState() {
        let vm = MuseAvatarViewModel()
        vm.setup()

        // Should not crash even without a loaded model
        let followEvent = StreamEvent(platform: "twitch", type: .follow, username: "user", displayName: "User")
        vm.reactToEvent(followEvent)

        let subEvent = StreamEvent(platform: "twitch", type: .subscribe, username: "sub", displayName: "Sub")
        vm.reactToEvent(subEvent)

        let donationEvent = StreamEvent(platform: "youtube", type: .donation, username: "donor", displayName: "Donor", amount: 10.0)
        vm.reactToEvent(donationEvent)

        let raidEvent = StreamEvent(platform: "twitch", type: .raid, username: "raider", displayName: "Raider")
        vm.reactToEvent(raidEvent)

        // All event types should be handled without crash
    }

    func testConversationStateStartsIdle() {
        let vm = MuseAvatarViewModel()
        XCTAssertEqual(vm.conversationState, .idle)
    }
}

// MARK: - StudioState Muse Mode Tests

final class StudioStateModeTests: XCTestCase {

    func testMuseVisualSource() {
        let muse = VisualSource.muse
        XCTAssertEqual(muse.rawValue, "Muse")
        XCTAssertEqual(muse.icon, "brain.head.profile")
        XCTAssertFalse(muse.description.isEmpty)
    }

    func testAllVisualSourcesCaseIterable() {
        let all = VisualSource.allCases
        XCTAssertTrue(all.contains(.face))
        XCTAssertTrue(all.contains(.avatar))
        XCTAssertTrue(all.contains(.muse))
    }
}

// MARK: - Twitch IRC Parser Tests

@MainActor
final class TwitchChatParsingTests: XCTestCase {

    func testTwitchClientInitialState() {
        let client = TwitchChatClient()
        XCTAssertFalse(client.isConnected)
        XCTAssertNil(client.oauthToken)
        XCTAssertNil(client.channel)
    }
}

// MARK: - YouTube Live Chat Client Tests

@MainActor
final class YouTubeLiveChatTests: XCTestCase {

    func testYouTubeClientInitialState() {
        let client = YouTubeLiveChatClient()
        XCTAssertFalse(client.isConnected)
        XCTAssertNil(client.apiKey)
        XCTAssertNil(client.liveChatId)
    }
}

// MARK: - SocialFeedProvider Tests

@MainActor
final class SocialFeedProviderTests: XCTestCase {

    func testInitialState() {
        let provider = SocialFeedProvider()
        XCTAssertFalse(provider.isConnected)
    }

    func testConnectSetsConnected() async throws {
        let provider = SocialFeedProvider()
        try await provider.connect()
        XCTAssertTrue(provider.isConnected)
        await provider.disconnect()
        XCTAssertFalse(provider.isConnected)
    }

    func testPollingInterval() {
        let provider = SocialFeedProvider()
        XCTAssertEqual(provider.pollingInterval, 30.0)

        provider.pollingInterval = 60.0
        XCTAssertEqual(provider.pollingInterval, 60.0)
    }
}

// MARK: - Emote Enum Tests

final class EmoteEnumTests: XCTestCase {

    func testAllExpectedEmotesExist() {
        // Verify key emotes used in the Muse pipeline are valid
        let emotes: [EmoteAnimationLayer.Emote] = [
            .wave, .nod, .excited, .bow, .jump, .clap,
            .thinking, .surprised, .laugh, .dance
        ]
        XCTAssertEqual(emotes.count, 10)

        // Verify raw values round-trip
        for emote in emotes {
            let reconstructed = EmoteAnimationLayer.Emote(rawValue: emote.rawValue)
            XCTAssertEqual(reconstructed, emote)
        }
    }

    func testCelebrateDoesNotExist() {
        // Verify we correctly migrated away from .celebrate
        let celebrate = EmoteAnimationLayer.Emote(rawValue: "celebrate")
        XCTAssertNil(celebrate, ".celebrate should not exist — use .excited instead")
    }
}
