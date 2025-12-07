# Arkavo App Integration Guide

This document describes the registration flow, verification checkpoints, and integration requirements between Arkavo apps and the backend services.

## Architecture Overview

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Arkavo App    │────▶│   authnz-rs      │────▶│  Arkavo Node    │
│   (iOS/macOS)   │     │ (Identity Server)│     │  (Blockchain)   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
        │                       │                        │
        │  WebAuthn/Passkey     │  NanoTDF Token         │  Smart Contracts
        │  DID Generation       │  User Registry         │  DID-Account Linking
        │  Profile Storage      │  DynamoDB              │  Access Control
        └───────────────────────┴────────────────────────┘
```

## Services & Endpoints

| Service | URL | Purpose |
|---------|-----|---------|
| Identity Server | `https://identity.arkavo.net` | WebAuthn registration/authentication |
| WebSocket | `wss://100.arkavo.net/ws` | Real-time P2P communication |
| Handle Check | `https://xrpc.arkavo.net` | ATProto handle availability |
| Arkavo Node | `ws://localhost:9944` | Blockchain RPC (local dev) |

---

## Registration Flow

### Step 1: EULA Acceptance

**User Action:** Accept End User License Agreement

**App State:**
- `RegistrationView` displays EULA
- Checkbox must be checked to proceed

**Verification:** None required (UI-only)

---

### Step 2: Handle (Username) Creation

**User Action:** Enter unique handle

**App Validation:**
- Minimum 3 characters
- Alphanumeric + hyphens only
- Lowercase

**Backend Check:**
```http
HEAD https://xrpc.arkavo.net/xrpc/com.atproto.identity.resolveHandle?handle={handle}.arkavo.social
```

**Response:**
- `404 Not Found` → Handle is available
- `200 OK` → Handle already taken

**Verification Checkpoint:**
```bash
# Check if handle is registered in ATProto
curl -I "https://xrpc.arkavo.net/xrpc/com.atproto.identity.resolveHandle?handle=testuser.arkavo.social"
```

---

### Step 3: DID Generation

**App Action:** Generate DID key pair in Secure Enclave

**Implementation:** `KeychainManager.generateAndSaveDIDKey()`

**DID Format:** `did:key:z<base58-encoded-P256-public-key>`

**Storage:**
- Private key: iOS Secure Enclave (hardware-protected)
- DID string: Keychain (`com.arkavo.webauthn` access group)

**Verification Checkpoint:**
```swift
// In app debug console
let did = KeychainManager.getDIDKey()
print("Generated DID: \(did)")
// Expected: did:key:z6Mk...
```

---

### Step 4: WebAuthn Registration

**App Action:** Register passkey with identity server

#### 4a. Fetch Registration Challenge

```http
GET https://identity.arkavo.net/register/{handle}?handle={handle}&did={did}
```

**Response:**
```json
{
  "challenge": "base64-encoded-challenge",
  "userID": "uuid-v4"
}
```

#### 4b. Create Passkey (Face ID/Touch ID)

**App:** Uses `ASAuthorizationPlatformPublicKeyCredentialProvider`

**Relying Party:** `identity.arkavo.net`

#### 4c. Complete Registration

```http
POST https://identity.arkavo.net/register
Content-Type: application/json

{
  "id": "credential-id",
  "rawId": "base64-raw-id",
  "response": {
    "clientDataJSON": "base64-client-data",
    "attestationObject": "base64-attestation"
  },
  "type": "public-key",
  "handle": "username",
  "did": "did:key:z6Mk..."
}
```

**Response Headers:**
```
x-auth-token: <NanoTDF-token>
```

**Verification Checkpoint:**
```bash
# Check DynamoDB for user record
aws dynamodb get-item \
  --table-name prod-credentials \
  --key '{"user_id": {"S": "uuid-from-registration"}}'
```

---

### Step 5: Token Storage

**App Action:** Save NanoTDF token to Keychain

**Storage:**
- Key: `authentication_token`
- Access Group: `com.arkavo.webauthn`
- Protection: `.whenUnlocked`

**Verification Checkpoint:**
```swift
// In app debug
let token = try KeychainManager.getAuthenticationToken()
print("Token saved: \(token != nil)")
```

---

### Step 6: Profile & Streams Creation

**App Action:** Create local profile and data streams

**Created Objects:**
1. `Profile` (SwiftData model)
   - `publicID`: SHA256 hash of UUID
   - `name`: User's display name
   - `handle`: `{username}.arkavo.social`
   - `did`: `did:key:z6Mk...`

2. `Account` (links to Profile)

3. `Streams` (3 default streams):
   - Video stream
   - Post stream
   - Inner Circle stream

**Verification Checkpoint:**
```swift
// Check profile was created
let account = try await persistenceController.getOrCreateAccount()
print("Profile DID: \(account.profile?.did ?? "none")")
print("Streams count: \(account.streams.count)") // Should be 3
```

---

### Step 7: WebSocket Connection

**App Action:** Establish authenticated WebSocket connection

```
wss://100.arkavo.net/ws
Authorization: Bearer <NanoTDF-token>
```

**P2P Key Exchange:**
- App sends public key for encrypted messaging
- Server responds with its public key

**Verification Checkpoint:**
```swift
// Check connection state
print("Client state: \(client.currentState)")
// Expected: .connected
```

---

## Post-Registration Verification Checklist

### On Identity Server (authnz-rs)

| Check | Command | Expected |
|-------|---------|----------|
| User in DynamoDB | `aws dynamodb scan --table-name prod-credentials --filter-expression "username = :h" --expression-attribute-values '{":h":{"S":"testuser"}}'` | User record exists |
| Handle reserved | `aws dynamodb get-item --table-name prod-handles --key '{"handle":{"S":"testuser"}}'` | Handle record exists |
| Credential count | Check `credential_ids` array in user record | At least 1 credential |

### On Arkavo Node (Blockchain)

After registration, the DID-to-account linking happens via the `linkAccountWithProof` RPC:

```bash
# Check if DID is linked on-chain
curl -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"arkavo_linkAccountWithProof","params":["user-uuid","did:key:z6Mk...","0x1234..."]}' \
  http://localhost:9933
```

**Response (Success):**
```json
{
  "success": true,
  "did": "did:key:z6Mk...",
  "address": "0x1234...",
  "user_id": "uuid",
  "error": null,
  "error_code": null
}
```

**Response (Error):**
```json
{
  "success": false,
  "error": "DID is already linked to another account",
  "error_code": "DID_ALREADY_LINKED"
}
```

### On App (Local)

| Check | Location | Expected |
|-------|----------|----------|
| Profile exists | SwiftData | `account.profile != nil` |
| DID stored | Keychain | `KeychainManager.getDIDKey() != nil` |
| Token stored | Keychain | `KeychainManager.getAuthenticationToken() != nil` |
| Handle stored | Keychain | `KeychainManager.getArkavoCredentials()?.handle != nil` |
| Streams created | SwiftData | `account.streams.count == 3` |

---

## Error Codes Reference

### RPC Error Codes (from arkavo-node)

| Code | Description | Resolution |
|------|-------------|------------|
| `INVALID_UUID` | Invalid user_id format | Ensure UUID v4 format |
| `INVALID_ADDRESS` | Invalid H160 address | Use 0x-prefixed 40-char hex |
| `INVALID_DID_FORMAT` | DID doesn't start with `did:key:` | Regenerate DID |
| `DID_TOO_LONG` | DID exceeds 256 bytes | Use standard did:key format |
| `CONTRACT_NOT_CONFIGURED` | Missing env vars | Set `USER_REGISTRY_ADDRESS` and `USER_REGISTRY_OWNER` |
| `DID_ALREADY_LINKED` | DID bound to another account | Use different DID or check existing link |
| `ACCOUNT_ALREADY_LINKED` | Address already has DID | Query existing DID for this address |
| `NOT_OWNER` | RPC caller not contract owner | Use correct owner account |
| `RUNTIME_ERROR` | Node runtime failure | Check node logs |

---

## Environment Configuration

### authnz-rs (Identity Server)

```env
# Server
PORT=8443
TLS_CERT_PATH=/path/to/fullchain.pem
TLS_KEY_PATH=/path/to/privkey.pem

# Cryptographic Keys
SIGN_KEY_PATH=/path/to/signkey.pem
ENCODING_KEY_PATH=/path/to/encodekey.pem
DECODING_KEY_PATH=/path/to/decodekey.pem

# DynamoDB
DYNAMODB_CREDENTIALS_TABLE=prod-credentials
DYNAMODB_HANDLES_TABLE=prod-handles
AWS_REGION=us-east-1

# Arkavo Node RPC (for DID linking)
ARKAVO_NODE_RPC=ws://localhost:9944
```

### Arkavo Node

```env
# User Registry Contract (for DID linking)
USER_REGISTRY_ADDRESS=0x1234567890abcdef1234567890abcdef12345678
USER_REGISTRY_OWNER=5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY
```

---

## Integration Test Workflow

### 1. Start Services

```bash
# Terminal 1: Start Arkavo Node
./target/release/arkavo-node --dev

# Terminal 2: Start authnz-rs
./target/release/authnz-rs
```

### 2. Deploy User Registry Contract

```bash
cargo contract instantiate \
  --url ws://127.0.0.1:9944 \
  --suri //Alice \
  --constructor new \
  --skip-confirm \
  --execute \
  contracts/target/ink/user_registry/user_registry.contract
```

### 3. Configure Environment

```bash
export USER_REGISTRY_ADDRESS=<contract-address-from-step-2>
export USER_REGISTRY_OWNER=5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY
```

### 4. Register User via App

Run the Arkavo app and complete registration flow.

### 5. Verify DID Linking

```bash
# Query contract directly
cargo contract call \
  --url ws://127.0.0.1:9944 \
  --contract $USER_REGISTRY_ADDRESS \
  --message get_account_by_did \
  --args "did:key:z6Mk..."
```

---

## Troubleshooting

### "Passkey Already Exists" Error

**Cause:** User previously registered with same relying party

**Resolution:**
1. Go to Settings → Passwords
2. Search for `identity.arkavo.net`
3. Delete existing passkeys
4. Retry registration

### "Connection Failed" Error

**Cause:** Cannot reach identity server

**Resolution:**
1. Check network connectivity
2. Verify `identity.arkavo.net` is reachable
3. Check certificate pinning (app may reject invalid certs)

### "DID Already Linked" Error

**Cause:** DID already bound to another blockchain address

**Resolution:**
1. Query existing link: `get_account_by_did(did)`
2. If user owns that address, use it
3. Otherwise, generate new DID (delete from Keychain first)

### Offline Mode Activation

**Cause:** App cannot connect to backend services

**State:** `sharedState.isOfflineMode = true`

**Behavior:**
- Local profile created with auto-generated name
- Limited functionality (no P2P messaging)
- "Try to Reconnect" button shown in UI
