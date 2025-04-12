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
