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
2. Initiation & Peer Confirmation (Integrated into GroupView/P2PGroupViewModel):

User Action: User taps the "Initiate Key Renewal" button in KeyStoreStatusView.
Precondition: Ensure the device is connected to at least one peer via the existing "InnerCircle" MCSession.
UI: Present a modal sheet:
List currently connected peers (from peerManager.connectedPeers/connectedPeerProfiles). Allow selection of one peer for renewal.
Display prompt: "Ask [Peer Name] to confirm key renewal on their device."
Include "Confirm Renewal" and "Cancel" buttons.
Mutual Confirmation:
Both users must tap "Confirm Renewal" on their respective devices.
When a user taps "Confirm Renewal", send a simple P2P message to the selected peer (e.g., struct KeyRenewalConfirmation {}). Define this message handling in P2PGroupViewModel.
State: Add state variables to P2PGroupViewModel to track the renewal state (e.g., AwaitingPeerSelection, AwaitingConfirmation, Generating, Exchanging, Failed, Success).

3. Mutual Key Generation (Triggered from P2PGroupViewModel, executed by ArkavoClient/OpenTDFKit):

Action: When a device has both sent its *own* KeyRenewalConfirmation and *received* one from the peer, proceed.
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
Extract the received public KeyStore data (`receivedPublicKeyStoreData`).
Use `PersistenceController` (or a relevant manager) to fetch the `Profile` associated with the sending peer's ID.
Access the peer's `PublicKeyStore` object (likely stored in `Profile.keyStorePublic`).
Update the *existing* peer `PublicKeyStore` object by calling its `deserialize(from: receivedPublicKeyStoreData)` method. This adds the newly received keys to the peer's store.
Save the updated peer `Profile` back using `PersistenceController`.
5. Verification & Confirmation (via P2PGroupViewModel):

Acknowledgement: After successfully processing the received peer KeyStore data (Step 4), send a simple acknowledgement message (e.g., struct KeyRenewalAcknowledgement {}) back to the peer.
Completion: When a P2PGroupViewModel has both successfully processed the received peer KeyStore and received the KeyRenewalAcknowledgement from the peer, the process is complete.
UI Update: Update the UI state to "Success", display the confirmation message, dismiss the renewal modal, and trigger refreshKeyStoreStatus to show the updated key count.
6. Error Handling (in P2PGroupViewModel and UI):

Implement timeouts for receiving confirmations, public key data, and acknowledgements.
If the P2P connection drops, update UI state to "Failed - Connection Lost", allow retry from the peer selection step.
If confirmation fails (user taps "Cancel" or timeout), abort the process.
If any step involving ArkavoClient, OpenTDFKit, or PersistenceController throws an error, update UI state to "Failed", show the error, and allow retry.
If acknowledgements aren't received within the timeout, assume failure, potentially requiring a full retry.

### InnerCircle: Trusted P2P Network

**Core Concept:** The InnerCircle utilizes direct Peer-to-Peer (P2P) communication, typically via frameworks like Multipeer Connectivity (`MCSession`), with the **primary goal of establishing verified trust between users**. This trusted P2P channel then serves the **secondary, crucial function of enabling secure exchanges**, such as the renewal of KeyStores for ongoing communication security. This approach emphasizes direct, user-controlled trust and secure operations, distinct from server-mediated interactions.

**Key Requirements Based on Current Implementation & Goals:**

1.  **P2P Trust Establishment & Verification:**
    *   **Connection Initiation:** Users can discover and initiate direct connections with nearby peers (likely using `MCSession`).
    *   **Mutual Confirmation (for Sensitive Operations):** Implement confirmation steps for sensitive actions like KeyStore renewal. This involves:
        *   UI prompts on both devices indicating the proposed action and the involved peer.
        *   Requiring explicit confirmation (e.g., tapping a "Confirm" button) from *both* users.
        *   Exchange of simple confirmation messages (e.g., `KeyRenewalConfirmation`) over the P2P channel to ensure mutual agreement before proceeding.
    *   **Trust Indicators:** Visual cues in the UI indicating P2P connection status (`connectedPeers`) and the health/status of the secure channel (e.g., `P2PGroupViewModel` states like `isKeyStoreLow`).

2.  **Secure P2P Communication (Enabled by Trust):**
    *   **Leverage KeyStore:** Utilize the established trusted P2P connection and `OpenTDFKit.KeyStore` / `OpenTDFKit.PublicKeyStore` for cryptographic operations (`Profile.keyStorePrivate`, `Profile.keyStorePublic`).
    *   **Secure Session Maintenance (Key Renewal):** Implement the detailed key renewal workflow, managed by `P2PGroupViewModel` and `ArkavoClient`, *after* mutual confirmation has been established for the operation:
        *   Detect low-key counts (`lowKeyThreshold`) - *Note: Current PublicKeyStore API doesn't expose counts directly; this detection needs alternative logic or API update.*
        *   Trigger user-initiated renewal with a selected peer.
        *   Perform mutual confirmation via UI and P2P messages (as described in point 1).
        *   Generate new key pairs locally (`keyStore.generateAndStoreKeyPairs()`).
        *   Securely exchange new public KeyStore data (`NewPublicKeyStoreData`) over the established P2P TDF channel.
        *   Receive the peer's new public KeyStore data (`receivedData`). Retrieve the peer's `Profile`. If the profile has existing `keyStorePublic` data, create a `PublicKeyStore` instance, deserialize `receivedData` into it (`publicKeyStore.deserialize(from: receivedData)`), serialize the updated store (`updatedData = await publicKeyStore.serialize()`), and save `updatedData` back to `Profile.keyStorePublic`. If no existing data, save `receivedData` directly to `Profile.keyStorePublic`. Save the updated profile via `PersistenceController`.
        *   Confirm successful exchange via acknowledgements (`KeyRenewalAcknowledgement`).
    *   **Transparent Security:** Provide clear status updates during sensitive operations like key renewal (e.g., "Awaiting Peer Selection", "Waiting for Peer Confirmation...", "Exchanging Keys", "Success", "Failed").

3.  **User Experience:**
    *   **Intentional Connection & Trust:** Design interactions that emphasize deliberate P2P connection and confirmation for sensitive actions.
    *   **Clear Status:** Users should easily understand their connection status with peers and the security state of their communication channels.

4.  **Privacy & Control:**
    *   **Direct Communication:** Emphasize that InnerCircle communication is primarily P2P, reinforcing user control and minimizing server reliance.
    *   **Revocation Workflow:** Define a clear process initiated when a peer's trust is compromised or reduced, leading to the disconnection of the P2P session, deletion/clearing of the peer's stored public key data (e.g., via `PersistenceController` interacting with `Profile.keyStorePublic`), and removal of the peer from the user's InnerCircle list.

5.  **Technical Foundation:**
    *   **P2P Framework:** Build upon `MCSession` (or similar) for discovery, connection, and data transmission.
    *   **ViewModel Integration:** Use `P2PGroupViewModel` (or similar) to manage the state and logic of P2P trust establishment, confirmation, and subsequent secure operations like key renewal.
    *   **Data Persistence:** Use `PersistenceController` for storing own keys (`Profile.keyStorePrivate` as `Data?`) and managing trusted peer profiles which contain their public keys (`Profile.keyStorePublic` as `Data?`). The initial `Profile.keyStorePrivate` is created and saved during the first successful P2P key exchange. Peer public keys (`Profile.keyStorePublic`) are added/updated by saving the received serialized `Data`. When needed, this `Data` is used to initialize a `PublicKeyStore` instance (e.g., `let store = PublicKeyStore(curve: .secp256r1); try await store.deserialize(from: profile.keyStorePublic!)`).
    *   **Offline Capability:** Leverage the inherent offline capabilities of P2P frameworks.

**Potential Future Enhancements (Not detailed in current CLAUDE.md):**

*   **Graduated Trust Levels:** Introduce formal tiers of trust.
*   **Connection Context:** Allow users to add notes about connections/trust.
*   **Alternative Verification Methods:** Support QR codes, etc., for initial trust.
*   **Granular Permissions:** Control data sharing based on established trust.
*   **Circle Management Tools:** UI for reviewing/managing trusted peers.
