import XCTest
@testable import Arkavo

/// Unit tests for FeatureConfig feature flag system
@MainActor
final class FeatureConfigTests: XCTestCase {
    var sut: FeatureConfig!
    let testStorageKey = "com.arkavo.enabledFeatures.test"

    override func setUp() async throws {
        // Clear UserDefaults before each test
        UserDefaults.standard.removeObject(forKey: testStorageKey)
        // Note: We can't easily test the singleton, so we test the logic
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: testStorageKey)
        sut = nil
    }

    // MARK: - Default Configuration Tests

    func testDefaultFeatures() {
        // Given: Fresh FeatureConfig instance
        // When: Checking default features
        let config = FeatureConfig.shared

        // Then: Non-social features should be enabled by default
        XCTAssertTrue(config.isEnabled(.agents), "Agents should be enabled by default")
        XCTAssertTrue(config.isEnabled(.p2p), "P2P should be enabled by default")
        XCTAssertTrue(config.isEnabled(.creator), "Creator should be enabled by default")
        XCTAssertFalse(config.isEnabled(.social), "Social should be disabled by default")
        XCTAssertFalse(config.isEnabled(.nfc), "NFC should be disabled by default")
    }

    // MARK: - Feature Toggle Tests

    func testEnableFeature() {
        // Given: FeatureConfig with social disabled
        let config = FeatureConfig.shared
        XCTAssertFalse(config.isEnabled(.social))

        // When: Enabling social feature
        config.enable(.social)

        // Then: Social should be enabled
        XCTAssertTrue(config.isEnabled(.social))
    }

    func testDisableFeature() {
        // Given: FeatureConfig with agents enabled
        let config = FeatureConfig.shared
        XCTAssertTrue(config.isEnabled(.agents))

        // When: Disabling agents feature
        config.disable(.agents)

        // Then: Agents should be disabled
        XCTAssertFalse(config.isEnabled(.agents))
    }

    func testEnableAlreadyEnabledFeature() {
        // Given: FeatureConfig with agents already enabled
        let config = FeatureConfig.shared
        config.enable(.agents)
        let initialCount = config.enabledFeatures.count

        // When: Trying to enable agents again
        config.enable(.agents)

        // Then: Should not add duplicate
        XCTAssertEqual(config.enabledFeatures.count, initialCount)
    }

    func testDisableAlreadyDisabledFeature() {
        // Given: FeatureConfig with social already disabled
        let config = FeatureConfig.shared
        config.disable(.social)
        let initialCount = config.enabledFeatures.count

        // When: Trying to disable social again
        config.disable(.social)

        // Then: Count should remain the same
        XCTAssertEqual(config.enabledFeatures.count, initialCount)
    }

    // MARK: - Bulk Operations Tests

    func testEnableMultipleFeatures() {
        // Given: FeatureConfig with some features
        let config = FeatureConfig.shared

        // When: Enabling multiple features at once
        let featuresToEnable: Set<FeatureConfig.Feature> = [.social, .nfc]
        config.enable(featuresToEnable)

        // Then: Both features should be enabled
        XCTAssertTrue(config.isEnabled(.social))
        XCTAssertTrue(config.isEnabled(.nfc))
    }

    func testSetEnabledFeatures() {
        // Given: FeatureConfig with default features
        let config = FeatureConfig.shared

        // When: Setting specific features only
        let newFeatures: Set<FeatureConfig.Feature> = [.social, .creator]
        config.setEnabledFeatures(newFeatures)

        // Then: Only specified features should be enabled
        XCTAssertTrue(config.isEnabled(.social))
        XCTAssertTrue(config.isEnabled(.creator))
        XCTAssertFalse(config.isEnabled(.agents))
        XCTAssertFalse(config.isEnabled(.p2p))
        XCTAssertFalse(config.isEnabled(.nfc))
    }

    func testResetToDefaults() {
        // Given: FeatureConfig with modified features
        let config = FeatureConfig.shared
        config.enable(.social)
        config.enable(.nfc)
        config.disable(.agents)

        // When: Resetting to defaults
        config.resetToDefaults()

        // Then: Should match default configuration
        XCTAssertTrue(config.isEnabled(.agents))
        XCTAssertTrue(config.isEnabled(.p2p))
        XCTAssertTrue(config.isEnabled(.creator))
        XCTAssertFalse(config.isEnabled(.social))
        XCTAssertFalse(config.isEnabled(.nfc))
    }

    func testEnableAllFeatures() {
        // Given: FeatureConfig with default features
        let config = FeatureConfig.shared

        // When: Enabling all features
        config.enableAllFeatures()

        // Then: All features should be enabled
        for feature in FeatureConfig.Feature.allCases {
            XCTAssertTrue(config.isEnabled(feature), "\(feature) should be enabled")
        }
    }

    // MARK: - Feature Metadata Tests

    func testFeatureDisplayNames() {
        // Verify all features have display names
        XCTAssertEqual(FeatureConfig.Feature.social.displayName, "Social Network")
        XCTAssertEqual(FeatureConfig.Feature.agents.displayName, "Agent Management")
        XCTAssertEqual(FeatureConfig.Feature.p2p.displayName, "P2P Messaging")
        XCTAssertEqual(FeatureConfig.Feature.creator.displayName, "Creator Tools")
        XCTAssertEqual(FeatureConfig.Feature.nfc.displayName, "NFC Key Exchange")
    }

    func testFeatureDescriptions() {
        // Verify all features have descriptions
        for feature in FeatureConfig.Feature.allCases {
            XCTAssertFalse(feature.description.isEmpty, "\(feature) should have a description")
        }
    }

    func testFeatureIcons() {
        // Verify all features have icons
        XCTAssertEqual(FeatureConfig.Feature.social.icon, "network")
        XCTAssertEqual(FeatureConfig.Feature.agents.icon, "cpu")
        XCTAssertEqual(FeatureConfig.Feature.p2p.icon, "antenna.radiowaves.left.and.right")
        XCTAssertEqual(FeatureConfig.Feature.creator.icon, "video.fill")
        XCTAssertEqual(FeatureConfig.Feature.nfc.icon, "wave.3.right")
    }

    // MARK: - Static Convenience Tests

    func testStaticFeatureFlags() {
        // Given: FeatureConfig with specific features
        let config = FeatureConfig.shared
        config.enable(.social)
        config.disable(.agents)

        // When: Checking via static convenience properties
        // Then: Should match config state
        XCTAssertEqual(FeatureFlags.socialNetworkEnabled, config.isEnabled(.social))
        XCTAssertEqual(FeatureFlags.agentDiscoveryEnabled, config.isEnabled(.agents))
        XCTAssertEqual(FeatureFlags.p2pMessagingEnabled, config.isEnabled(.p2p))
        XCTAssertEqual(FeatureFlags.creatorToolsEnabled, config.isEnabled(.creator))
        XCTAssertEqual(FeatureFlags.nfcEnabled, config.isEnabled(.nfc))
    }
}
