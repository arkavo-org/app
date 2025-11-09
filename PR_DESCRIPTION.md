# Make Arkavo social network features optional

## Summary

This PR implements a feature flag system that makes Arkavo's social network features (authentication and WebSocket) optional, allowing the app to run in different modes based on user needs.

### Three Operating Modes

1. **Full Mode**: All features including social network
2. **P2P Mode**: Local agents + WiFi messaging only
3. **Offline Mode**: Recording and local processing only

## Changes

### 1. Feature Flag System (`FeatureFlags.swift`)

- New `FeatureConfig` class manages 5 features:
  - `.social` - Arkavo social network (auth, WebSocket, profiles)
  - `.agents` - Edge agent management
  - `.p2p` - WiFi/MultipeerConnectivity
  - `.creator` - Camera, VRM, recording
  - `.nfc` - NFC key exchange (not yet implemented)

- Persists to UserDefaults
- Defaults to non-social features: agents, p2p, creator

### 2. Conditional Social Connection (`ArkavoApp.swift`)

- `ArkavoClient` always initialized (needed for P2P encryption)
- Only connects to network when `.social` feature enabled
- Automatically enters offline mode when social disabled
- Feature config available as environment object

### 3. Dynamic Tab Navigation (`ContentView.swift`)

- Tabs conditionally shown based on enabled features
- Social tab hidden when feature disabled or offline
- Agents tab only shown when enabled
- New `availableTabs` computed property

### 4. Feature Settings UI (`FeatureSettingsView.swift`)

- Toggle features on/off with descriptions
- Reset to defaults or enable all features
- Handles side effects (tab switching, offline mode)

## Architecture

The key insight is that `ArkavoClient` serves two purposes:
1. **Social network**: Authentication, WebSocket, profile sync
2. **Encryption**: P256 key exchange for P2P messaging

By keeping `ArkavoClient` initialized but not connecting unless social features are enabled, we achieve:
- ✅ P2P messaging works without social network
- ✅ Agent management remains independent
- ✅ Creator tools function offline
- ✅ Users control their privacy and feature set

## Benefits

- **Privacy**: Disable cloud authentication entirely
- **Offline Support**: Core features work without network
- **Resource Efficiency**: Only initialize needed services
- **Flexibility**: Enterprise deployments can disable social
- **Modularity**: Easier to add/remove features

## File Changes

```
Arkavo/Arkavo/FeatureFlags.swift         (new)    - Feature flag system
Arkavo/Arkavo/FeatureSettingsView.swift  (new)    - Settings UI
Arkavo/Arkavo/ArkavoApp.swift            (modified) - Conditional connection
Arkavo/Arkavo/ContentView.swift          (modified) - Dynamic tabs
```

## Testing Needed

- [ ] Build succeeds on iOS 18+, iPadOS 18+, macOS 15+
- [ ] Social tab appears/disappears based on feature flag
- [ ] Agents tab appears/disappears based on feature flag
- [ ] P2P messaging works with social disabled
- [ ] Agent discovery works with social disabled
- [ ] Creator tools work in offline mode
- [ ] Settings view toggles features correctly
- [ ] App doesn't crash when switching feature states

## Related

This exploration addresses the requirement to make social network features optional while preserving:
- Edge agent management
- Creator tools (camera, VRM, recording)
- P2P/WiFi key exchange
- NFC support (when implemented)

## Future Enhancements

- [ ] Extract encryption service abstraction (for full P2P independence)
- [ ] Add reconnection logic when re-enabling social features
- [ ] Onboarding flow to select features on first launch
- [ ] Per-feature telemetry to understand usage patterns
- [ ] Add settings access from profile tab
