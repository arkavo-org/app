/// Centralized feature flags for App Store review gating.
/// Flip these to `true` to re-enable features post-approval.
enum FeatureFlags {
    /// AI Agent discovery, chat, tools, and budget
    static let aiAgent = false
    /// VRM/Muse avatar rendering and face tracking
    static let avatar = false
    /// Remote camera bridge (WebSocket server for iOS companion)
    static let remoteCameraBridge = false
    /// C2PA provenance verification and display
    static let provenance = false
    /// Content protection (TDF3, HLS, FairPlay) and Iroh publishing
    static let contentProtection = false
    /// Arkavo encrypted streaming platform
    static let arkavoStreaming = false
    /// YouTube streaming and OAuth integration
    static let youtube = false
    /// Patreon patron management
    static let patreon = false
    /// Workflow management section
    static let workflow = false
    /// Marketing/social section
    static let social = false
    /// Muse roles (Producer, Publicist, Sidekick) powered by MLX
    static let localAssistant = true
}
