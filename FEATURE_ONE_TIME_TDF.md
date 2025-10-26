# Feature Branch: one-time-tdf

## Overview
This feature branch introduces peer-to-peer encryption using One-Time TDF (Trusted Data Format) along with comprehensive contacts management and Inner Circle functionality.

## New Behaviors and Features

### 1. One-Time TDF (Trusted Data Format)
- **NanoTDF v13 Implementation**: Secure message encryption without requiring KAS server for Inner Circle members
- **Direct P2P Decryption**: Messages between trusted peers decrypt locally without server round-trips
- **Key Derivation**: Uses HKDF (HMAC-based Key Derivation Function) with backwards compatibility
- **Automatic Key Exchange**: Seamless key regeneration and exchange between connected peers

### 2. Contacts Management System
- **ContactsView**: New dedicated view for managing trusted connections
- **Connection Methods**:
  - "Connect Nearby": P2P discovery for local connections
  - "Invite Remotely": Share invitation links for remote connections
- **Contact Features**:
  - Online/offline status indicators
  - Encryption status badges
  - Swipe-to-delete functionality
  - Contact detail views with messaging options

### 3. Inner Circle Functionality
- **GroupInnerCircleView**: Dedicated interface for managing trusted group members
- **Key Exchange Status**: Real-time tracking with states (idle, in progress, completed, failed)
- **Key Management**: Visual indicators showing available public/private key counts
- **Member Controls**:
  - Direct messaging
  - Manual key exchange triggers
  - P2P connection management
  - Remove from Inner Circle

### 4. Enhanced Empty State UX
- **WaveEmptyStateView**: Animated wave design with Arkavo logo
- **Context-Aware Messaging**: Different messages based on current tab/view
- **Consistent Design**: Unified empty state across Contacts, Groups, and other views

### 5. Profile and Trust Management
- **Profile Deletion**: `deletePeerProfile()` removes contacts and all associated data
- **Trust Revocation**: `deleteKeyStoreDataFor()` revokes trust while preserving profile
- **Cascading Cleanup**: Automatic removal of associated chats when deleting contacts

### 6. Group Enhancements
- **P2P Protocol Improvements**: Multi-state key exchange with better error handling
- **Connection Tracking**: Timestamps and status for each peer connection
- **Automatic Profile Sharing**: Profiles shared automatically when peers connect
- **Direct Member Messaging**: Message group members directly from group view

### 7. Technical Improvements
- **Duplicate Stream Prevention**: Fixed issue where streams were created multiple times on restart
- **Video Broadcast**: Improved NanoTDF handling for video content
- **Testing Infrastructure**: iOS simulator automation with IDB companion
- **EULA Compliance**: Redesigned EULA following Apple Human Interface Guidelines

## Key Files Modified

### New Files
- `ContactsView.swift` - Main contacts interface
- `ContactsCreateView.swift` - Contact creation flow
- `GroupInnerCircleView.swift` - Inner Circle management
- `OfflineHomeView.swift` - Offline state handling
- `WaveEmptyStateView.swift` - Empty state UI component

### Significantly Modified
- `GroupViewModel.swift` - Added Inner Circle logic and P2P key exchange
- `ChatViewModel.swift` - One-time TDF encryption/decryption
- `KeyStoreData.swift` - Enhanced key management
- `ArkavoMessageRouter.swift` - P2P message routing
- `PersistenceController.swift` - Contact and profile persistence

## Testing
- New test suites for key exchange scenarios
- Automated UI testing with iOS simulator
- Integration tests for P2P connectivity

## Migration Notes
- Existing groups will need to re-establish Inner Circle connections
- Key stores will be migrated automatically to support new format
- No data loss expected during migration