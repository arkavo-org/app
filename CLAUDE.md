# CLAUDE.md - Arkavo Project Guide

## Build/Test Commands
- Open workspace: `open Arkavo.xcworkspace`
- Build main app: `xcodebuild -scheme Arkavo -quiet -sdk iphoneos -destination 'generic/platform=iOS,name=Any iOS Device' build`
- Test all: `xcodebuild test -workspace Arkavo.xcworkspace -scheme Arkavo -destination 'platform=iOS Simulator,name=iPhone 15'`
- Test single class: `xcodebuild test -workspace Arkavo.xcworkspace -scheme Arkavo -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:ArkavoTests/ArkavoTests`
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
    - Cards: Custom views like `ImmersiveThoughtCard` serve as containers, often taking up the full screen or large portions.
    - Input fields: `TextEditor` is used for multi-line input, styled for the specific context (e.g., clear background, placeholder text).
    - Custom components: Reusable views like `ClusterAnnotationView`, `GroupChatIconList`, `ContributorsView` are created for specific UI needs.
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

### One-time TDF
One-time TDF (Trusted Data Format) provides perfect forward secrecy communications:

This plan integrates the renewal workflow into the existing architecture (P2PGroupViewModel, ArkavoClient, Profile model, etc.).

1. Threshold Detection & Triggering:

Mechanism: In P2PGroupViewModel, enhance the arkavoClientDidUpdateKeyStatus delegate method (or wherever refreshKeyStoreStatus gets its data).
Logic: Compare keyCount against capacity (using the lowKeyThreshold percentage, e.g., 10%).
State: Add a @Published var isKeyStoreLow: Bool property to P2PGroupViewModel/PeerDiscoveryManager. Update it based on the threshold check.
UI Prompt: In GroupView (specifically KeyStoreStatusView), observe isKeyStoreLow. When true, display the warning text ("Your one-time keys...") and potentially change the "Regenerate Keys" button to "Initiate Key Renewal with Peer" or enable a dedicated button.
2. Initiation & Peer Verification (Integrated into GroupView/P2PGroupViewModel):

User Action: User taps the "Initiate Key Renewal" button in KeyStoreStatusView.
Precondition: Ensure the device is connected to at least one peer via the existing "InnerCircle" MCSession.
UI: Present a modal sheet:
List currently connected peers (from peerManager.connectedPeers/connectedPeerProfiles). Allow selection of one peer for renewal.
Visual Verification:
Generate a short, temporary verification code (e.g., 6 random digits).
Send this code unencrypted to the selected peer using a new, simple P2P message type (e.g., struct KeyRenewalVerificationCode: Codable { let code: String }) over the existing MCSession. Define this message handling in P2PGroupViewModel.
Display the received code prominently on the modal sheet. Add text: "Ask your peer ['Peer Name'] to read the code displayed on their device. Does it match the code you see below?"
Include "Confirm Match" and "Cancel" buttons. Both users must tap "Confirm Match" only after visually verifying the codes match on both screens.
State: Add state variables to P2PGroupViewModel to track the renewal state (e.g., AwaitingPeerSelection, AwaitingVerificationCode, AwaitingConfirmation, Generating, Exchanging, Failed, Success).
3. Mutual Key Generation (Triggered from P2PGroupViewModel, executed by ArkavoClient/OpenTDFKit):

Action: When both users tap "Confirm Match" (signalled via another simple P2P message, e.g., struct KeyRenewalConfirmation {}), proceed.
Backend Call: Each P2PGroupViewModel calls a new method on ArkavoClient, e.g., func generateAndPrepareNewKeyStore() async throws -> Data.
ArkavoClient Logic:
Calls OpenTDFKit's KeyStore generation function (e.g., keyStore.regenerateKeys()).
Retrieves the newly serialized private KeyStore data.
Uses PersistenceController to update the local user's Profile.keyStorePrivate field with this new private data.
Retrieves the newly serialized public KeyStore data.
Returns this public data.
4. Mutual Public KeyStore Exchange (via P2PGroupViewModel and ArkavoClient):

Sending: The P2PGroupViewModel takes the public KeyStore data returned by arkavoClient.generateAndPrepareNewKeyStore().
Message: Create a new message type (e.g., struct NewPublicKeyStoreData: Codable { let publicKeyStore: Data }).
Encryption & Sending: Encrypt this NewPublicKeyStoreData message using the standard P2P TDF mechanism (P2PGroupViewModel.sendSecureData or a similar method calling arkavoClient.encryptAndSendPayload) and send it to the verified peer over the existing MCSession.
Receiving: In P2PGroupViewModel's message handling (e.g., arkavoClientDidReceiveMessage delegate or equivalent P2P data handler), detect the NewPublicKeyStoreData message type.
Processing Received Data:
Extract the received public KeyStore data.
Call a new ArkavoClient method, e.g., func storeReceivedPeerKeyStore(profileID: Data, publicKeyStoreData: Data) async throws.
ArkavoClient Logic: Uses PersistenceController.savePeerProfile (or a dedicated method) to find the peer's Profile by profileID and update its keyStorePublic field with the publicKeyStoreData.
5. Verification & Confirmation (via P2PGroupViewModel):

Acknowledgement: After successfully storing the received peer KeyStore data (Step 4), send a simple acknowledgement message (e.g., struct KeyRenewalAcknowledgement {}) back to the peer.
Completion: When a P2PGroupViewModel has both successfully stored the received peer KeyStore and received the KeyRenewalAcknowledgement from the peer, the process is complete.
UI Update: Update the UI state to "Success", display the confirmation message, dismiss the renewal modal, and trigger refreshKeyStoreStatus to show the updated key count.
6. Error Handling (in P2PGroupViewModel and UI):

Implement timeouts for receiving verification codes, confirmations, public key data, and acknowledgements.
If the P2P connection drops, update UI state to "Failed - Connection Lost", allow retry from the peer selection step.
If visual verification fails (user taps "Cancel"), abort the process.
If any step involving ArkavoClient or PersistenceController throws an error, update UI state to "Failed", show the error, and allow retry.
If acknowledgements aren't received within the timeout, assume failure, potentially requiring a full retry.

### InnerCircle: Trusted P2P Network

**Core Concept:** The InnerCircle utilizes direct Peer-to-Peer (P2P) communication, typically via frameworks like Multipeer Connectivity (`MCSession`), with the **primary goal of establishing verified trust between users**. This trusted P2P channel then serves the **secondary, crucial function of enabling secure exchanges**, such as the renewal of KeyStores for ongoing communication security. This approach emphasizes direct, user-controlled trust and secure operations, distinct from server-mediated interactions.

**Key Requirements Based on Current Implementation & Goals:**

1.  **P2P Trust Establishment & Verification:**
    *   **Connection Initiation:** Users can discover and initiate direct connections with nearby peers (likely using `MCSession`).
    *   **Mutual Verification (for Sensitive Operations):** Implement robust verification processes, like the visual code matching described for key renewal, to confirm the identity of the peer before proceeding with sensitive actions. This includes:
        *   Generating and displaying a short code on both devices.
        *   Transmitting the code via an unencrypted P2P message (`KeyRenewalVerificationCode`).
        *   Require explicit confirmation (`KeyRenewalConfirmation`) from *both* users after visual matching.
    *   **Trust Indicators:** Visual cues in the UI indicating P2P connection status (`connectedPeers`) and the health/status of the secure channel (e.g., `P2PGroupViewModel` states like `isKeyStoreLow`).

2.  **Secure P2P Communication (Enabled by Trust):**
    *   **Leverage KeyStore:** Utilize the established trusted P2P connection and `OpenTDFKit.KeyStore` for cryptographic operations (`Profile.keyStorePrivate`, `Profile.keyStorePublic`).
    *   **Secure Session Maintenance (Key Renewal):** Implement the detailed key renewal workflow, managed by `P2PGroupViewModel` and `ArkavoClient`, *after* trust has been verified for the operation:
        *   Detect low-key counts (`lowKeyThreshold`).
        *   Trigger user-initiated renewal with a selected, verified peer.
        *   Perform mutual verification (as part of trust establishment, see point 1).
        *   Generate new key pairs locally (`keyStore.regenerateKeys()`).
        *   Securely exchange new public KeyStore data (`NewPublicKeyStoreData`) over the established P2P TDF channel.
        *   Receive and store the peer's new public KeyStore data (`PersistenceController.savePeerProfile`).
        *   Confirm successful exchange via acknowledgements (`KeyRenewalAcknowledgement`).
    *   **Transparent Security:** Provide clear status updates during sensitive operations like key renewal (e.g., "Awaiting Peer Selection", "Verifying Peer...", "Exchanging Keys", "Success", "Failed").

3.  **User Experience:**
    *   **Intentional Connection & Trust:** Design interactions that emphasize deliberate P2P connection and trust verification.
    *   **Clear Status:** Users should easily understand their connection status with peers and the security state of their communication channels.

4.  **Privacy & Control:**
    *   **Direct Communication:** Emphasize that InnerCircle communication is primarily P2P, reinforcing user control and minimizing server reliance.
    *   **Revocation Workflow:** Define a clear process initiated when a peer's trust is compromised or reduced, leading to the disconnection of the P2P session, deletion of the peer's stored public key data (`Profile.keyStorePublic` via `PersistenceController`), and removal of the peer from the user's InnerCircle list.

5.  **Technical Foundation:**
    *   **P2P Framework:** Build upon `MCSession` (or similar) for discovery, connection, and data transmission.
    *   **ViewModel Integration:** Use `P2PGroupViewModel` (or similar) to manage the state and logic of P2P trust establishment, verification, and subsequent secure operations like key renewal.
    *   **Data Persistence:** Use `PersistenceController` for storing own keys (`Profile.keyStorePrivate`) and trusted peer public keys (`Profile.keyStorePublic`). The initial `Profile.keyStorePrivate` is created and saved during the first successful P2P key exchange.
    *   **Offline Capability:** Leverage the inherent offline capabilities of P2P frameworks.

**Potential Future Enhancements (Not detailed in current CLAUDE.md):**

*   **Graduated Trust Levels:** Introduce formal tiers of trust.
*   **Connection Context:** Allow users to add notes about connections/trust.
*   **Alternative Verification Methods:** Support QR codes, etc., for initial trust.
*   **Granular Permissions:** Control data sharing based on established trust.
*   **Circle Management Tools:** UI for reviewing/managing trusted peers.
