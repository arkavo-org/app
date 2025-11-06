# HYPΞRforum

> A cyber-renaissance communication platform where humans collaborate with assistance from real-time AI agent councils.

## Overview

HYPΞRforum (HΞR) is a macOS application that enables structured discussions where each participant has access to their own AI Council that supplements insights without replacing human judgment, promoting augmented discourse.

## Features

### Phase 1 (MVP)

- **Core Chat**: Real-time group discussions with threading, topic tagging, and stream-based access control
- **Council Integration**: Inline AI agent availability, on-demand insights, and research mode
- **Onboarding**: Passkey authentication via WebAuthn, profile creation, and group joining
- **Security**: OpenTDF/NanoTDF message encryption, end-to-end encrypted communications

## Technology Stack

- **Platform**: macOS 26+
- **Language**: Swift 6.2
- **Framework**: SwiftUI
- **Architecture**:
  - ArkavoSocial: P2P social features and OpenTDF encryption
  - ArkavoAgent: AI agent framework for Council functionality
  - ArkavoContent: Content management
  - ArkavoMediaKit: Media handling with DRM support

## Security Architecture

- **Authentication**: Passkeys/WebAuthn for passwordless identity
- **Encryption**: OpenTDF/NanoTDF for message protection
- **Privacy**: On-device AI inference capability
- **Networking**: Zero-trust networking model
- **Communications**: End-to-end encrypted Council interactions

## Branding

- **Primary Name**: HYPΞRForum
- **Shortmark**: HΞR
- **Symbol**: Greek Xi (Ξ) with Neural Circuit Glow styling
- **Aesthetic**: Optimistic cyberpunk tone
- **Colors**: Arkavo Orange palette (#FF6600)

## Project Structure

```
HYPERforum/
├── HYPERforum/
│   ├── HYPERforumApp.swift      # Main app entry point
│   ├── ContentView.swift         # Main UI views
│   ├── Assets.xcassets/          # App icons and colors
│   ├── HYPERforum.entitlements  # Security entitlements
│   └── Info.plist               # App metadata
├── HYPERforumTests/             # Unit tests
└── HYPERforumUITests/           # UI tests
```

## Building

1. Open `HYPERforum.xcodeproj` in Xcode 16.1+
2. Select the HYPERforum scheme
3. Build and run (⌘R)

The project automatically links to the shared Arkavo packages via local Swift Package Manager references.

## Development Roadmap

### M1: Branding & Identity ✓
- Logo variants
- App icons
- Arkavo Orange color palette
- Cyberpunk aesthetic

### M2: Core Architecture (TBD)
- WebSocket real-time messaging
- OpenTDF encryption integration
- Passkey authentication flow

### M3: Group Discussions (TBD)
- Thread management
- Topic tagging
- Member management

### M4: AI Council (TBD)
- Agent initialization
- On-demand insights
- Research mode
- Context awareness

### M5: Polish & Launch (TBD)
- Accessibility verification
- Performance optimization
- App Store assets
- Documentation

## Requirements

- macOS 26+
- Xcode 16.1+
- Swift 6.2

## Related Issue

This app implements [GitHub Issue #159](https://github.com/arkavo-org/app/issues/159)

## License

Copyright © 2025 Arkavo. All rights reserved.
