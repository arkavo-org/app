# Arkavo Security Implementation

## Overview

This document outlines the security features and best practices implemented in the Arkavo iOS application to protect user data and ensure secure communication.

## Table of Contents

1. [Secure Memory & Data Protection](#secure-memory--data-protection)
2. [Keychain Security](#keychain-security)
3. [Network Security](#network-security)
4. [Cryptographic Operations](#cryptographic-operations)
5. [Logging & Debug Safety](#logging--debug-safety)
6. [Certificate Pinning](#certificate-pinning)
7. [Security Checklist](#security-checklist)

---

## Secure Memory & Data Protection

### Database Encryption

**Implementation:** `PersistenceController.swift:35-43`

The SwiftData persistent store uses iOS Data Protection with `FileProtectionType.complete`:

```swift
try FileManager.default.setAttributes(
    [.protectionKey: FileProtectionType.complete],
    ofItemAtPath: url.path
)
```

**Protection Level:**
- Data encrypted when device is locked
- Requires device unlock to access database
- Hardware-backed encryption using Secure Enclave

### Temporary File Protection

**Implementation:**
- `VideoManager.swift:106-109`
- `VideoCreateView.swift:850-853`

All temporary video files use `FileProtectionType.completeUntilFirstUserAuthentication`:

```swift
try? FileManager.default.setAttributes(
    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
    ofItemAtPath: tempDir.path
)
```

---

## Keychain Security

### Enhanced Keychain Storage

**Implementation:** `KeychainManager.swift:28-30`

All keychain items now use:
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` - Accessible only when unlocked, never syncs
- `kSecUseDataProtectionKeychain` - Uses data protection keychain (hardware-backed)

```swift
kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
kSecUseDataProtectionKeychain as String: true as AnyObject,
```

### Secure Enclave Integration

**Implementation:** `KeychainManager.swift:304-336`

DID key generation uses Secure Enclave:

```swift
kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
```

**Protected Items:**
- WebAuthn credentials
- OAuth tokens (Patreon, Reddit, Bluesky, YouTube)
- Authentication tokens
- DID/Handle pairs
- JWT signing keys
- P2P encryption keys

### JWT Signing Key Management

**Implementation:** `AuthenticationManager.swift:483-507`

JWT signing keys are now persistent and stored in Keychain:

```swift
private func getOrCreateJWTSigningKey() -> SymmetricKey? {
    // Retrieves existing key or generates new 256-bit key
    // Stores in keychain at "com.arkavo.jwt"/"signing-key"
}
```

**Previous Issue:** ❌ New key generated per JWT (signatures unverifiable)
**Fixed:** ✅ Persistent key stored in hardware-backed keychain

---

## Network Security

### HTTPS Enforcement

All network communication uses HTTPS with TLS 1.2+.

### URLSession Configuration

**Implementation:** `AuthenticationManager.swift:34-41`

Secure URLSession configuration:

```swift
config.timeoutIntervalForRequest = 30
config.timeoutIntervalForResource = 60
config.httpCookieAcceptPolicy = .never
config.httpShouldSetCookies = false
```

**Security Features:**
- No cookie storage
- Certificate pinning enabled
- Timeout protection against slowloris attacks

### Protected Endpoints

All requests to these domains use secure URLSession with certificate pinning:
- `webauthn.arkavo.net` - WebAuthn authentication
- `kas.arkavo.net` - Key Access Service
- `app.arkavo.com` - Application API

---

## Certificate Pinning

### Implementation

**File:** `CertificatePinningDelegate.swift`

Certificate pinning validates server certificates against known public key hashes to prevent Man-in-the-Middle (MITM) attacks.

### Configuration

**Pinned Domains:**
```swift
private let pinnedDomains: Set<String> = [
    "webauthn.arkavo.net",
    "kas.arkavo.net",
    "app.arkavo.com",
]
```

**How to Add Certificate Hashes:**

1. Extract public key hash from your server certificate:
```bash
openssl x509 -in cert.pem -pubkey -noout | \
  openssl pkey -pubin -outform der | \
  openssl dgst -sha256 -binary | \
  openssl enc -base64
```

2. Add to `CertificatePinningDelegate.swift`:
```swift
private let pinnedPublicKeyHashes: Set<String> = [
    "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
    "sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=", // Backup cert
]
```

### Development Mode

To disable pinning during development:
```swift
certificatePinningDelegate.isPinningEnabled = false
```

---

## Cryptographic Operations

### Secure Enclave Usage

**DID Key Generation** (`KeychainManager.swift:297-349`)
- EC P-256 keys stored in Secure Enclave
- Private keys never leave secure hardware
- Biometric authentication can be required

**Key Features:**
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- `kSecAttrTokenIDSecureEnclave`
- `.privateKeyUsage` access control

### Data Encryption

**P2P Encryption:**
- AES-256-GCM for data encryption
- ECDH (Elliptic Curve Diffie-Hellman) for key exchange
- HKDF for key derivation

**TDF Encryption:**
- OpenTDF format for content protection
- Ephemeral keys for each encryption
- Policy-based access control

---

## Logging & Debug Safety

### SecureLogger Implementation

**File:** `SecureLogger.swift`

Prevents sensitive data exposure in logs:

```swift
// ❌ BAD - Logs sensitive data
print("Token: \(authToken)")

// ✅ GOOD - Redacts in production
SecureLogger.logToken(label: "Auth Token", token: authToken)
// Output (Production): "Auth Token: [REDACTED] (128 chars)"
// Output (Debug): "Auth Token: eyJhbGciOi... (128 chars)"
```

### Usage Examples

**Logging Cryptographic Keys:**
```swift
SecureLogger.logCryptoKey(label: "Signing Key", keyData: keyData)
// Production: "Signing Key: [CRYPTO_KEY_REDACTED]"
// Debug: "Signing Key: Key size 256 bits"
```

**Logging Sensitive Data:**
```swift
SecureLogger.logSensitiveData(label: "Encrypted Payload", data: encryptedData)
// Production: "Encrypted Payload: 2048 bytes [REDACTED]"
// Debug: "Encrypted Payload: 2048 bytes [a1b2c3d4...e5f6g7h8]"
```

**Logging Auth Events:**
```swift
SecureLogger.logAuth("User authenticated successfully")
SecureLogger.logSecurity("Certificate validation succeeded")
SecureLogger.logSecurityViolation("Invalid signature detected")
```

### Data Extension

```swift
let data = Data(...)
print(data.secureDescription)
// Production: "2048 bytes [REDACTED]"
// Debug: "2048 bytes [a1b2c3d4...e5f6g7h8]"
```

---

## Security Checklist

### ✅ Implemented Features

- [x] **Database encryption** with FileProtection.complete
- [x] **Keychain security** with hardware-backed storage
- [x] **Secure Enclave** integration for DID keys
- [x] **Certificate pinning** for HTTPS connections
- [x] **Temporary file protection** for video data
- [x] **JWT signing key** persistent storage
- [x] **Secure logging** with automatic redaction
- [x] **Data protection** for all keychain items
- [x] **HTTPS enforcement** for all API calls
- [x] **No cookie storage** in secure sessions

### 🔒 Security Features

| Feature | Status | Location |
|---------|--------|----------|
| Database Encryption | ✅ | PersistenceController.swift:35 |
| Keychain Data Protection | ✅ | KeychainManager.swift:28-30 |
| Secure Enclave Keys | ✅ | KeychainManager.swift:324 |
| Certificate Pinning | ✅ | CertificatePinningDelegate.swift |
| Secure Logging | ✅ | SecureLogger.swift |
| JWT Key Persistence | ✅ | AuthenticationManager.swift:483 |
| Temp File Protection | ✅ | VideoManager.swift:106 |
| No Secrets in Code | ✅ | Secrets.swift (gitignored) |

---

## Configuration Requirements

### Entitlements Required

**File:** `Arkavo.entitlements`

```xml
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)com.arkavo.Arkavo</string>
    <string>$(AppIdentifierPrefix)com.arkavo.webauthn</string>
    <string>$(AppIdentifierPrefix)com.arkavo.jwt</string>
</array>
```

### Build Configuration

1. **Release builds:**
   - All sensitive logging automatically redacted
   - Certificate pinning enabled
   - Debug statements removed

2. **Debug builds:**
   - Limited sensitive data logging (hash previews only)
   - Certificate pinning can be disabled
   - Full debug information available

---

## Threat Model

### Protected Against

✅ **Device Compromise (Locked State)**
- All data encrypted when device locked
- Keychain protected by device passcode
- Secure Enclave keys cannot be extracted

✅ **Man-in-the-Middle Attacks**
- Certificate pinning validates server identity
- TLS 1.2+ enforced
- No fallback to insecure connections

✅ **Memory Dump Attacks**
- Sensitive data cleared from memory when backgrounded
- Hardware-backed encryption for keys
- No secrets in application binary

✅ **Log Analysis**
- Production builds redact all sensitive data
- No tokens/keys/credentials in logs
- Minimal attack surface

### Limitations

⚠️ **Device Compromise (Unlocked State)**
- Database accessible when device unlocked
- Memory can be read while app running
- **Mitigation:** Use biometric authentication, auto-lock

⚠️ **Backup Attacks**
- Keychain items with `ThisDeviceOnly` not backed up ✅
- Database encrypted but included in backups
- **Mitigation:** Use `excludeFromBackup` for sensitive files

---

## Incident Response

### Security Violation Detection

Certificate pinning failures trigger:
1. Connection rejected
2. Security log entry
3. User notification (optional)

```swift
SecureLogger.logSecurityViolation("Certificate pinning FAILED - Potential MITM")
```

### Key Rotation

To rotate JWT signing key:
```swift
try? KeychainManager.delete(service: "com.arkavo.jwt", account: "signing-key")
// New key will be generated on next createJWT() call
```

### Certificate Updates

When server certificates change:
1. Get new certificate hash (see Certificate Pinning section)
2. Add to `pinnedPublicKeyHashes` set
3. Keep old hash for transition period
4. Remove old hash after migration complete

---

## Best Practices

### For Developers

1. **Never log sensitive data** - Use `SecureLogger` instead of `print()`
2. **Use secure sessions** - Always use `secureURLSession` for API calls
3. **Validate inputs** - Check all user/server data before processing
4. **Clear sensitive data** - Overwrite buffers containing keys/tokens
5. **Use Keychain** - Never store secrets in UserDefaults or files

### Code Review Checklist

- [ ] No `print()` statements with tokens/keys/credentials
- [ ] URLSession calls use certificate pinning delegate
- [ ] Temporary files have FileProtection set
- [ ] New secrets added to Keychain (not hardcoded)
- [ ] Sensitive operations use Secure Enclave when possible

---

## References

- [Apple Security Framework](https://developer.apple.com/documentation/security)
- [Data Protection API](https://developer.apple.com/documentation/uikit/protecting_the_user_s_privacy/encrypting_your_app_s_files)
- [Keychain Services](https://developer.apple.com/documentation/security/keychain_services)
- [Certificate Pinning Guide](https://owasp.org/www-community/controls/Certificate_and_Public_Key_Pinning)

---

## Version History

- **2025-01-06** - Initial security hardening implementation
  - Added database encryption
  - Enhanced keychain security
  - Implemented certificate pinning
  - Created secure logging framework
  - Fixed JWT key persistence issue
  - Added temporary file protection
