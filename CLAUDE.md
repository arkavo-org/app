# CLAUDE.md - Arkavo Project Guide

## Build/Test Commands
- Open workspace: `open Arkavo.xcworkspace`
- Build main app: `xcodebuild -workspace Arkavo.xcworkspace -scheme Arkavo -destination "platform=iOS Simulator,name=iPhone 16 Pro Max,OS=18.4,arch=arm64" -quiet build`
- Test all: `xcodebuild test -workspace Arkavo.xcworkspace -scheme Arkavo -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max,OS=18.4,arch=arm64'`
- Test single class: `xcodebuild test -workspace Arkavo.xcworkspace -scheme Arkavo -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max,OS=18.4,arch=arm64' -only-testing:ArkavoTests/ArkavoTests`
- Format code: `swiftformat --swiftversion 6.0 .`
- Package tests: `cd ArkavoSocial && swift test`

## Code Style
- **Naming**: PascalCase for types, camelCase for variables/functions
- **Architecture**: MVVM pattern with clean separation of concerns
- **Imports**: Group imports with Foundation/SwiftUI first, then alphabetical
- **Error Handling**: Use descriptive custom Error types with specific cases
- **Async**: Prefer async/await over completion handlers
- **Comments**: Use /// for documentation comments
- **SwiftUI**: Views as structs, ViewModels as ObservableObject classes
- **Protocols**: Protocol-oriented design with protocol extensions
- **Files**: One main type per file, grouped by feature
- **Refactoring**: Keep changes focused and to a minimum - modify only what's needed for the task

## UI Style
- **HIG Compliance**: Follow Apple's Human Interface Guidelines where applicable, but expect custom components and interactions.
- **Layout & Spacing**:
    - Utilize a base `systemMargin` (e.g., 16pt) often applied via `.padding()` or used in multiples (e.g., `systemMargin * 2`, `systemMargin * 8`).
    - Specific padding values (e.g., 40pt) are also used contextually.
    - Respect safe areas, sometimes using `.ignoresSafeArea()` for full-screen experiences.
- **Navigation**:
    - Employs custom navigation patterns. Examples include:
        - State-driven view switching controlled by variables (e.g., `selectedView` in `ArkavoView`).
        - Menu overlays for accessing different sections.
        - Full-screen, vertically swipeable cards for content feeds (e.g., `PostFeedView`).
- **Typography**:
    - Primarily uses specific font sizes and weights via `.font(.system(size: ..., weight: ...))`. Examples: `size: 24, weight: .heavy`, `size: 14, weight: .bold`, `.headline`.
    - Dynamic Type styles (`.largeTitle`, `.body`, etc.) do not appear to be in common use; test scaling.
- **Colors**:
    - Uses a mix of explicit colors (e.g., `Color.black`, `.white`, `.blue`, `.gray`) and opacity (`.opacity(...)`).
    - Some system colors like `Color(.systemBackground)` are used, indicating partial support for light/dark mode adaptability.
    - Ensure color contrast is sufficient, especially with custom color combinations.
- **Components**:
    - Buttons: Styled using modifiers like `.padding`, `.background(Color...)`, `.foregroundColor`, `.cornerRadius()`. Style varies by context.
    - Cards: Custom views like `ThoughtView` or components within `StreamCloudView` serve as containers.
    - Input fields: `TextEditor` is used for multi-line input, styled for the specific context (e.g., clear background, placeholder text).
    - Custom components: Reusable views like `ClusterAnnotationView`, `GroupChatIconList`, `AccountProfileBadge` are created for specific UI needs.
- **Gestures & Feedback**:
    - Standard gestures like `DragGesture` (for swiping) are implemented.
    - Visual feedback is provided for interactions (e.g., button state changes, animations).
    - Ensure minimum touch targets (44x44pt recommended) are met, especially for smaller interactive elements.
- **Accessibility**:
    - Dynamic Type support needs verification due to the use of fixed font sizes.
    - Review and add explicit VoiceOver labels for controls and content where necessary.
    - Test using Accessibility Inspector to identify issues.
- **Animations**:
    - Uses SwiftUI animations (`.animation()`, `withAnimation`). Examples include `.spring()` and `.easeInOut`.
    - Transitions like `.move(edge: .bottom)` are used for view presentation.
    - Aim for purposeful and performant animations.

## Key Features

### One-time TDF Key Regeneration (P2P)

Securely regenerate `OpenTDFKit.KeyStore` keys between two directly connected peers using a P2P protocol managed by `P2PGroupViewModel`. This ensures ongoing secure communication even if previous keys are compromised (Perfect Forward Secrecy concept).

**Protocol Overview:**

1.  **Initiation (Initiator):**
    *   User triggers regeneration (e.g., via UI in `GroupView`) with a connected peer (`PeerDiscoveryManager.initiateKeyRegeneration`).
    *   `P2PGroupViewModel` sends `KeyRegenerationRequest` P2P message to the selected peer. State: `.requestSent`.
2.  **Offer (Responder):**
    *   `P2PGroupViewModel` receives `KeyRegenerationRequest`.
    *   Sends back `KeyRegenerationOffer` P2P message containing its own nonce. State: `.offerSent`.
3.  **Acknowledgement & Initiator Key Gen (Initiator):**
    *   `P2PGroupViewModel` receives `KeyRegenerationOffer`.
    *   Sends `KeyRegenerationAcknowledgement` P2P message (with original nonce). State: `.ackSent`.
    *   **Triggers Local Key Generation:** Calls `P2PGroupViewModel.performKeyGenerationAndSave()`:
        *   Generates 8192 new key pairs using `OpenTDFKit.KeyStore`.
        *   Serializes the *private* KeyStore data.
        *   Fetches the *peer's* `Profile` from SwiftData.
        *   Saves the serialized *local private* KeyStore data into the *peer's* `Profile.keyStorePrivate` field using `PersistenceController.savePeerProfile()`.
        *   Exports the *public* KeyStore data from the newly generated keys.
    *   Sends `KeyStoreShare` P2P message containing the *local public* KeyStore data to the peer.
4.  **Commit & Responder Key Gen (Responder):**
    *   `P2PGroupViewModel` receives `KeyRegenerationAcknowledgement`.
    *   Sends `KeyRegenerationCommit` P2P message. State: `.commitSent`.
    *   **Triggers Local Key Generation:** Calls `P2PGroupViewModel.performKeyGenerationAndSave()` (same logic as Initiator in Step 3, saving *local private* keys to the *peer's* Profile record).
    *   Sends `KeyStoreShare` P2P message containing the *local public* KeyStore data to the peer.
5.  **Key Store Share & Completion (Both):**
    *   **(Initiator):** Receives `KeyRegenerationCommit`. State: `.commitReceivedWaitingForKeys`.
    *   **(Both):** `P2PGroupViewModel.handleKeyStoreShare` receives the `KeyStoreShare` message from the peer:
        *   Decodes the `KeyStoreSharePayload` containing the peer's public KeyStore data.
        *   Fetches the *sender's (peer's)* `Profile` from SwiftData.
        *   Saves the received *peer's public* KeyStore data into the *peer's* `Profile.keyStorePublic` field using `PersistenceController.savePeerProfile()`.
        *   Checks current key exchange state (`peerKeyExchangeStates`). If state was `.commitSent` (Responder) or `.commitReceivedWaitingForKeys` (Initiator), transitions state to `.completed`.
    *   Protocol finishes when both peers reach the `.completed` state after exchanging `KeyStoreShare` messages.

**Key Implementation Details:**

*   **State Management:** `P2PGroupViewModel.peerKeyExchangeStates: [MCPeerID: KeyExchangeTrackingInfo]` tracks the `KeyExchangeState` enum for each peer.
*   **P2P Messages:** Uses custom Codable structs (`KeyRegenerationRequest`, `KeyRegenerationOffer`, etc.) wrapped in a `P2PMessage` envelope, sent via `P2PGroupViewModel.sendP2PMessage` over `MCSession`.
*   **Key Storage:**
    *   The *local user's* newly generated *private* keys for the P2P relationship are stored in the *peer's* `Profile.keyStorePrivate` field in the local SwiftData store.
    *   The *peer's* received *public* keys are stored in the *peer's* `Profile.keyStorePublic` field.
*   **Error Handling:** `P2PError` enum covers failures; states transition to `.failed` on error.
*   **Threshold Detection:** *Currently missing.* The `CLAUDE.md` previously mentioned detecting low key counts (`localKeyStoreInfo`, `lowKeyThreshold`), but the `P2PGroupViewModel` implementation removed `localKeyStoreInfo` and related threshold logic. UI/trigger logic needs update if this feature is desired.

### InnerCircle: Trusted P2P Network

**Core Concept:** The InnerCircle utilizes direct Peer-to-Peer (P2P) communication via Multipeer Connectivity (`MCSession`) managed by `P2PGroupViewModel` and exposed via `PeerDiscoveryManager`. The primary goal is establishing a trusted P2P channel for secure operations like Key Regeneration.

**Key Requirements & Implementation:**

1.  **P2P Trust Establishment & Verification:**
    *   **Connection:** Uses `MCNearbyServiceAdvertiser`, `MCBrowserViewController`, and `MCSession` for discovery and connection. `PeerDiscoveryManager` provides UI access and manages state (`connectedPeers`, `connectionStatus`).
    *   **Identification:** Peers exchange `profileID` (Base58 Public Key) during discovery (`discoveryInfo`) and invitation (`context`). `P2PGroupViewModel.peerIDToProfileID` maps `MCPeerID` to profile IDs.
    *   **Profile Sharing (Optional):** Peers can explicitly share their `Profile` data via the `profileShare` P2P message, handled by `handleProfileShare`, which saves the peer's profile locally using `PersistenceController`.
    *   **Secure Operation Confirmation (Key Regen):** The Key Regeneration protocol itself acts as mutual confirmation through its request/offer/ack/commit steps.

2.  **Secure P2P Communication (Enabled by Trust):**
    *   **Key Regeneration:** The primary secure operation implemented is the Key Regeneration protocol described above.
    *   **Secure Data/Text:** `PeerDiscoveryManager.sendSecureData` and `sendSecureTextMessage` leverage `ArkavoClient.encryptAndSendPayload` (details TBD based on `ArkavoClient` implementation) to send encrypted data over the P2P channel. Received encrypted data (not fitting `P2PMessage` format) is posted via `NotificationCenter.default.post(name: .nonJsonDataReceived, ...)` for handling (likely by `ArkavoMessageRouter`).
    *   **Decrypted Text Storage:** Decrypted P2P text messages are stored locally as `Thought` objects associated with the relevant `Stream` using `P2PGroupViewModel.storeP2PMessageAsThought`.

3.  **User Experience:**
    *   `GroupView` likely uses `PeerDiscoveryManager` to display connection status, connected peers (`connectedPeerProfiles`), and potentially initiate actions like key regeneration.
    *   Key Regeneration state is tracked in `PeerDiscoveryManager.peerKeyExchangeStates`.

4.  **Privacy & Control:**
    *   Communication is primarily P2P via `MCSession`.
    *   Users explicitly connect and initiate sensitive operations like key regeneration.
    *   **Revocation (Disconnection):** `PeerDiscoveryManager.disconnectPeer` calls `P2PGroupViewModel.disconnectPeer`, which cancels the `MCSession` connection. The `MCSessionDelegate` callback (`session(_:peer:didChange:.notConnected)`) handles cleanup: removing the peer from `connectedPeers`, clearing associated maps (`peerIDToProfileID`, `connectedPeerProfiles`, `peerKeyExchangeStates`), and closing active `InputStream`s. *Note: This does not automatically delete the peer's `Profile` or associated `KeyStore` data from SwiftData; that requires a separate manual action.*

5.  **Technical Foundation:**
    *   **P2P Framework:** `MultipeerConnectivity` (`MCSession`, `MCNearbyServiceAdvertiser`, `MCBrowserViewController`). Delegates (`MCSessionDelegate`, `MCNearbyServiceAdvertiserDelegate`, etc.) are implemented by `P2PGroupViewModel`.
    *   **ViewModel:** `P2PGroupViewModel` (internal logic), `PeerDiscoveryManager` (facade for UI).
    *   **Data Persistence:** `PersistenceController` (SwiftData).
        *   **Permanent Identity Keys:** Assumed managed securely outside `Profile` (e.g., Keychain via `ArkavoClient`).
        *   **P2P Relationship Keys (Generated during Key Regeneration):**
            *   `peerProfile.keyStorePrivate` (`Data?`): Stores **local user's private keys** generated for encrypting *to this specific peer*.
            *   `peerProfile.keyStorePublic` (`Data?`): Stores the **peer's public keys** received via `KeyStoreShare` message.
        *   **Key Exchange Protocol:** Implemented within `P2PGroupViewModel` (`initiateKeyRegeneration`, `handleKeyRegenerationRequest`, etc.).
    *   **Cryptography:** `OpenTDFKit.KeyStore` for key generation (`performKeyGenerationAndSave`), serialization/deserialization. `ArkavoClient` is used for general secure message encryption/decryption (implementation details assumed).
    *   **Concurrency:** `@MainActor` used extensively for UI updates. `Task` used for background work and bridging `nonisolated` delegate methods.

**Potential Future Enhancements (Not detailed in current CLAUDE.md):**

*   **Formal Trust Levels:** Introduce tiers beyond simple connection.
*   **Alternative Verification:** QR codes, etc., for initial trust bootstrapping.
*   **Granular Permissions:** Control data sharing based on trust.
*   **UI for Peer Management:** Dedicated UI for reviewing/managing trusted peers and explicitly revoking trust (deleting associated Profile/KeyStore data).
*   **Re-implement Key Store Threshold Detection:** Add back logic to monitor `KeyStore` counts (requires `OpenTDFKit` API support or alternative tracking) and trigger UI warnings/prompts for regeneration in `PeerDiscoveryManager` / `GroupView`.
