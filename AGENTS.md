# Repository Guidelines

## Project Structure & Module Organization
Arkavo iOS target and app lifecycle code live in `Arkavo/Arkavo`. Unit tests reside in `Arkavo/ArkavoTests`; UI regression suites live in `Arkavo/ArkavoUITests`. The Swift packages `ArkavoContent`, `ArkavoCreator`, and `ArkavoSocial` hold reusable content, creator tooling, and peer-to-peer utilities; keep package-specific tests alongside their sources. Shared automation and IDB helpers are in `automation/`, and simulator artifacts should land in `test_results/`.

## Key Features

### One-Time TDF Encryption
The app implements One-Time TDF (Trusted Data Format) combining one-time pad encryption with TDF for perfect forward secrecy. Each message uses a unique symmetric key that is discarded after use. See README.md for detailed technical implementation.

### Contacts Management
- **ContactsView**: Search, filter, and manage contacts with swipe-to-delete gestures
- **ContactsCreateView**: Add new contacts with peer discovery
- **WaveEmptyStateView**: Animated empty state for contact lists

### Inner Circle Group Messaging
Secure peer-to-peer group messaging with the following features:
- **GroupViewModel**: Comprehensive P2P messaging with 8-state key exchange protocol
- **GroupInnerCircleView**: Manage trusted peers in inner circle groups
- **Key Exchange Protocol States**:
  1. `idle` - No exchange in progress
  2. `requestSent/requestReceived` - Key regeneration initiation
  3. `offerSent/offerReceived` - Public key offer exchange
  4. `ackSent/ackReceived` - Acknowledgement phase
  5. `commitSent/commitReceivedWaitingForKeys` - Final commitment
  6. `completed` - Exchange successful with new keystores
  7. `failed` - Exchange failed with error message
- **Automatic Key Renewal**: Monitors key usage and initiates renewal when running low
- **Trust Revocation**: Immediate disconnection and keystore deletion for untrusted peers

### Offline Support
- **OfflineHomeView**: Graceful degradation when network is unavailable

## Build, Test, and Development Commands
- `open Arkavo.xcworkspace` opens the workspace in Xcode for iterative development.
- `xcodebuild -workspace Arkavo.xcworkspace -scheme Arkavo -destination "platform=iOS Simulator,name=iPhone 16 Pro Max,OS=18.4,arch=arm64" -quiet build` performs a clean command-line build of the main app.
- `xcodebuild test -workspace Arkavo.xcworkspace -scheme Arkavo -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max,OS=18.4,arch=arm64'` runs the full simulator test suite; append `-only-testing:ArkavoTests/Name` to focus on a case.
- `swiftformat --swiftversion 6.2 .` enforces repository formatting before review.
- `cd ArkavoSocial && swift test` validates the social package in isolation.

## Coding Style & Naming Conventions
Adopt Swift 6 defaults: four-space indentation, trailing commas only where SwiftFormat permits, and `UpperCamelCase` for types, `lowerCamelCase` for functions, properties, and test methods. Keep public APIs documented briefly; avoid temporary or conversational comments. Run SwiftFormat before pushing to guarantee consistent diffs.

## Testing Guidelines
Add unit tests beside each feature in `ArkavoTests` and instrumented scenarios under `ArkavoUITests`. Mirror type names with `NameTests` classes and group methods by behavior. Achieve coverage for encryption, networking, and simulator flows when adding features. Use the simulator destination above to reproduce failures, and capture required screenshots into `test_results/`.

## Commit & Pull Request Guidelines
Write commit subjects in present tense (`Fix Sendable conformance warnings`), keep bodies focused on intent, and reference GitHub issues when applicable. Pull requests should summarize changes, link tracking issues, note testing performed, and attach relevant simulator screenshots. Flag configuration updates or security-sensitive changes explicitly and request targeted reviews.

## Simulator & Tooling Notes
Boot the iPhone 16 Pro Max simulator with `xcrun simctl boot "iPhone 16 Pro Max"` before running commands. Keep IDB companion running when using automation (`automation/idb_automation_fix.sh` provides tap helpers). Store screenshots and logs under `test_results/` rather than personal folders to keep history auditable.
