# CLAUDE.md - Arkavo Project Guide

## Build/Test Commands
- Open workspace: `open Arkavo.xcworkspace`
- Build main app: `xcodebuild -scheme Arkavo -sdk macosx -configuration Release build`
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