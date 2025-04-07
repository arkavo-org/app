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

## Key Features

### One-time TDF
One-time TDF (Trusted Data Format) provides perfect forward secrecy for peer-to-peer communications:

1. **Architecture**:
   - KeyStore maintains a pool of 8192 keys per device
   - Only public keys are shared between peers via PublicKeyStore
   - InnerCircle stream uses MultipeerConnectivity for P2P messaging

2. **Implementation Details**:
   - Each encryption operation uses a unique key
   - The key is permanently removed after a single use
   - Keys are automatically regenerated when running low
   - P2P messages are sent directly between devices
   - UI shows connection status and active peers

3. **Testing**:
   - Verify peer discovery between devices
   - Test manual peer selection via MCBrowserViewController
   - Confirm key exchange and one-time usage
   - Validate secure message delivery
   - Check proper key rotation